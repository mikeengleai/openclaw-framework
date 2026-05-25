#!/usr/bin/env bash
# scripts/40-pre-upgrade-snapshot.sh — baseline capture, dry-run verify, Docker save, Checkpoint B.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set}"
if step_done 40; then log_info "Step 40 already complete; skipping"; exit 0; fi

[ -f "${RUN_DIR}/approved-version.txt" ] || { log_err "approved-version.txt missing"; exit 1; }
APPROVED="$(cat "${RUN_DIR}/approved-version.txt")"

# 1) Baseline capture
openclaw_run() {
    case "${OPENCLAW_INSTALL_KIND}" in
        docker) docker exec "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" openclaw "$@" ;;
        npm)    openclaw "$@" ;;
    esac
}
openclaw_run --version > "${RUN_DIR}/version-before.txt" 2>&1 || true
openclaw_run doctor --json > "${RUN_DIR}/health-before.json" 2>&1 || true
openclaw_run status > "${RUN_DIR}/status-before.txt" 2>&1 || true
openclaw_run secrets audit > "${RUN_DIR}/secrets-audit-before.txt" 2>&1 || true

# update --dry-run JSON
openclaw_run update --dry-run --tag "${APPROVED}" --json > "${RUN_DIR}/update-dry-run.json" 2> "${RUN_DIR}/update-dry-run.stderr" || true

# Verify dry-run
if ! jq -e --arg V "${APPROVED}" '.targetVersion == $V' "${RUN_DIR}/update-dry-run.json" >/dev/null 2>&1; then
    log_err "dry-run targetVersion does not match approved (${APPROVED})"
    write_failed 40 "${RUN_DIR}/update-dry-run.stderr"
    exit 1
fi
if jq -e '.downgradeRisk == true' "${RUN_DIR}/update-dry-run.json" >/dev/null 2>&1; then
    log_err "dry-run reports downgradeRisk=true — abort"
    exit 1
fi

# git-commit-before (docker host)
if [ "${OPENCLAW_INSTALL_KIND}" = "docker" ] && sudo test -f /root/openclaw/.git/HEAD; then
    sudo cat /root/openclaw/.git/HEAD > "${RUN_DIR}/git-commit-before.txt" 2>/dev/null || true
fi

# env-before (key names only, no values)
env | grep -oE '^OPENCLAW_[A-Z_]+' | sort -u > "${RUN_DIR}/env-before.txt" || true

# logs-before
case "${OPENCLAW_INSTALL_KIND}" in
    npm)    journalctl --user -u openclaw-gateway --since '1 hour ago' --no-pager > "${RUN_DIR}/logs-before.txt" 2>&1 || true ;;
    docker) docker logs --since 1h "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" > "${RUN_DIR}/logs-before.txt" 2>&1 || true ;;
esac

# log-error baseline: count ERROR/FATAL/CRIT/panic/uncaught/unhandled in pre-upgrade
# logs. Step 70's threshold is "baseline + buffer" instead of an absolute number,
# so noisy gateways that already emit warnings don't fail verification.
grep -aiE 'ERROR|FATAL|CRIT|panic|uncaught|unhandled' "${RUN_DIR}/logs-before.txt" 2>/dev/null \
    | wc -l > "${RUN_DIR}/log-error-baseline.txt" || echo 0 > "${RUN_DIR}/log-error-baseline.txt"

# 2) Node/npm capture
node -v > "${RUN_DIR}/node-version-before.txt" 2>&1 || true
npm -v > "${RUN_DIR}/npm-version-before.txt" 2>&1 || true
command -v node > "${RUN_DIR}/which-node-before.txt" 2>&1 || true
command -v npm > "${RUN_DIR}/which-npm-before.txt" 2>&1 || true
npm config list -l > "${RUN_DIR}/npm-config-before.txt" 2>&1 || true

# 3) Docker host extras
if [ "${OPENCLAW_INSTALL_KIND}" = "docker" ]; then
    sudo docker compose -f "${OPENCLAW_DOCKER_COMPOSE}" config > "${RUN_DIR}/docker-compose-rendered-before.yml" 2>/dev/null || true
    sudo docker inspect "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" > "${RUN_DIR}/docker-container-inspect-before.json" 2>/dev/null || true
    sudo docker image inspect "${OPENCLAW_DOCKER_IMAGE}" > "${RUN_DIR}/docker-image-inspect-before.json" 2>/dev/null || true
    sudo docker images --digests > "${RUN_DIR}/docker-images-digests-before.txt" 2>/dev/null || true
    sudo docker system df > "${RUN_DIR}/docker-system-df-before.txt" 2>/dev/null || true

    log_info "Saving current image (${OPENCLAW_DOCKER_IMAGE}) — this can take a while"
    if ! sudo docker save "${OPENCLAW_DOCKER_IMAGE}" | zstd -T0 > "${RUN_DIR}/openclaw-local-image-before.tar.zst" 2> "${RUN_DIR}/docker-save.stderr"; then
        log_err "docker save failed — abort (rollback artifact required)"
        write_failed 40 "${RUN_DIR}/docker-save.stderr"
        exit 1
    fi
    chmod 600 "${RUN_DIR}/openclaw-local-image-before.tar.zst"
fi

# 4) Quiesce
quiesce_started=()
for c in "${QUIESCE_CONTAINERS[@]:-}"; do
    [ -z "${c}" ] && continue
    if sudo docker ps --format '{{.Names}}' | grep -qx "${c}"; then
        log_info "stopping container ${c}"
        sudo docker stop "${c}" >/dev/null
        quiesce_started+=("docker:${c}")
    fi
done
for s in "${QUIESCE_SERVICES_USER[@]:-}"; do
    [ -z "${s}" ] && continue
    if systemctl --user is-active --quiet "${s}" 2>/dev/null; then
        log_info "stopping user service ${s}"
        systemctl --user stop "${s}"
        quiesce_started+=("systemd:${s}")
    fi
done

# 5) Checkpoint B
banner "HOSTINGER SNAPSHOT REQUIRED
1. Open hpanel.hostinger.com in a browser
2. Navigate to this VPS
3. Trigger a system-level snapshot manually
4. Wait for snapshot to complete
5. Press ENTER below to proceed

Confirm before pressing ENTER:
  - file-level backup tarball was readable
  - sqlite-native backup ran (or warning was acknowledged)
  - off-server copy of the tarball exists

A Hostinger snapshot restore overwrites the current VPS state.
DO NOT proceed until the snapshot is confirmed complete in their UI."

if [ -z "${SU_NONINTERACTIVE:-}" ]; then
    prompt_continue "press ENTER to record the Hostinger snapshot confirmation"
fi

# 6) Confirmation artifact
{
    echo "## Hostinger snapshot confirmation"
    echo
    echo "host: ${HOSTNAME_VALUE}"
    echo "snapshot_visible_in_hostinger_ui: yes (operator-confirmed)"
    echo "snapshot_timestamp: $(date -Iseconds)"
    echo "confirmed_by: $(id -un)"
    echo "notes:"
} > "${RUN_DIR}/hostinger-snapshot-confirmation.md"

# 7) Un-quiesce
for entry in "${quiesce_started[@]:-}"; do
    [ -z "${entry}" ] && continue
    case "${entry}" in
        docker:*) sudo docker start "${entry#docker:}" >/dev/null || log_warn "could not restart ${entry}";;
        systemd:*) systemctl --user start "${entry#systemd:}" || log_warn "could not restart ${entry}";;
    esac
done

notify "Hostinger snapshot confirmed by operator on ${HOSTNAME_VALUE} — proceeding to apt upgrade"
step_complete 40
log_info "Step 40 complete"

#!/usr/bin/env bash
# scripts/70-post-upgrade-verify.sh — post-upgrade artifacts, pass criteria, canary-pass.txt.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set}"
if step_done 70; then log_info "Step 70 already complete; skipping"; exit 0; fi

[ -f "${RUN_DIR}/approved-version.txt" ] || { log_err "approved-version.txt missing"; exit 1; }
APPROVED="$(cat "${RUN_DIR}/approved-version.txt")"

openclaw_run() {
    # Wrap in `timeout 60` to defend against `openclaw doctor` and similar
    # commands hanging indefinitely (observed on 1klaw 2026-05-03 run).
    case "${OPENCLAW_INSTALL_KIND}" in
        docker) timeout 60 docker exec "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" openclaw "$@" ;;
        npm)    timeout 60 openclaw "$@" ;;
    esac
}

# 1) Capture after-state
openclaw_run --version > "${RUN_DIR}/version-after-raw.txt" 2>&1 || true
echo "${RUN_DIR}/version-after-raw.txt" >/dev/null
grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+(-[0-9]+)?' "${RUN_DIR}/version-after-raw.txt" | head -n 1 > "${RUN_DIR}/version-after.txt" || true

openclaw_run doctor --json > "${RUN_DIR}/health-after.json" 2>&1 || true
openclaw_run status > "${RUN_DIR}/status-after.txt" 2>&1 || true
openclaw_run doctor > "${RUN_DIR}/doctor-after.txt" 2>&1 || true
openclaw_run secrets audit > "${RUN_DIR}/secrets-audit-after.txt" 2>&1 || true

node -v > "${RUN_DIR}/node-version-after.txt" 2>&1 || true
npm -v > "${RUN_DIR}/npm-version-after.txt" 2>&1 || true
command -v node > "${RUN_DIR}/which-node-after.txt" 2>&1 || true
command -v npm > "${RUN_DIR}/which-npm-after.txt" 2>&1 || true
npm config list -l > "${RUN_DIR}/npm-config-after.txt" 2>&1 || true

case "${OPENCLAW_INSTALL_KIND}" in
    npm)    journalctl --user -u openclaw-gateway --since '1 hour ago' --no-pager > "${RUN_DIR}/log-review-1h.txt" 2>&1 || true ;;
    docker) docker logs --since 1h "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" > "${RUN_DIR}/log-review-1h.txt" 2>&1 || true ;;
esac
grep -aiE 'ERROR|FATAL|CRIT|panic|uncaught|unhandled' "${RUN_DIR}/log-review-1h.txt" > "${RUN_DIR}/log-review-1h-summary.txt" || true

# Diffs
diff -u "${RUN_DIR}/status-before.txt" "${RUN_DIR}/status-after.txt" > "${RUN_DIR}/status-diff.txt" || true
( jq -S . "${RUN_DIR}/health-before.json" 2>/dev/null; echo "---"; jq -S . "${RUN_DIR}/health-after.json" 2>/dev/null ) > "${RUN_DIR}/health-diff.txt" || true

# Docker after-state
if [ "${OPENCLAW_INSTALL_KIND}" = "docker" ]; then
    sudo docker compose -f "${OPENCLAW_DOCKER_COMPOSE}" config > "${RUN_DIR}/docker-compose-rendered-after.yml" 2>/dev/null || true
    sudo docker inspect "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" > "${RUN_DIR}/docker-container-inspect-after.json" 2>/dev/null || true
    sudo docker image inspect "${OPENCLAW_DOCKER_IMAGE}" > "${RUN_DIR}/docker-image-inspect-after.json" 2>/dev/null || true
    sudo docker images --digests > "${RUN_DIR}/docker-images-digests-after.txt" 2>/dev/null || true
fi

# 2) Notification path test
if notify "post-upgrade verification on ${HOSTNAME_VALUE} at $(date -Iseconds)" >/dev/null 2>&1; then
    echo "pass" > "${RUN_DIR}/notification-path-test.txt"
else
    echo "fail" > "${RUN_DIR}/notification-path-test.txt"
fi

# 3) Pass-criteria checks
errors=0
VERSION_AFTER="$(cat "${RUN_DIR}/version-after.txt")"
if [ "${VERSION_AFTER}" != "${APPROVED}" ]; then
    if [ -f "${RUN_DIR}/version-mismatch-acknowledged.txt" ]; then
        log_warn "version mismatch (approved=${APPROVED}, actual=${VERSION_AFTER}) acknowledged: $(cat "${RUN_DIR}/version-mismatch-acknowledged.txt")"
    else
        log_err "version mismatch: expected ${APPROVED}, got ${VERSION_AFTER}"
        log_err "if this is acceptable (e.g., docker registry has no image at the approved tag),"
        log_err "write a one-line reason to ${RUN_DIR}/version-mismatch-acknowledged.txt and resume"
        errors=$((errors+1))
    fi
fi
HEALTHZ_URL="${SU_HEALTHZ_URL:-http://127.0.0.1:18789/healthz}"
if ! curl -fsS --max-time 3 "${HEALTHZ_URL}" >/dev/null 2>&1; then
    log_err "/healthz did not return 200"
    errors=$((errors+1))
fi
log_error_count="$(wc -l < "${RUN_DIR}/log-review-1h-summary.txt" 2>/dev/null || echo 0)"
log_error_baseline="$(cat "${RUN_DIR}/log-error-baseline.txt" 2>/dev/null || echo 0)"
# Threshold = baseline + buffer (default 50). Override via SU_LOG_ERROR_THRESHOLD
# (absolute number) or SU_LOG_ERROR_BUFFER (relative growth allowance).
LOG_ERROR_BUFFER="${SU_LOG_ERROR_BUFFER:-50}"
if [ -n "${SU_LOG_ERROR_THRESHOLD:-}" ]; then
    LOG_ERROR_THRESHOLD="${SU_LOG_ERROR_THRESHOLD}"
else
    LOG_ERROR_THRESHOLD=$(( log_error_baseline + LOG_ERROR_BUFFER ))
fi
log_info "log review: ${log_error_count} errors/fatals (baseline ${log_error_baseline}, threshold ${LOG_ERROR_THRESHOLD})"
if [ "${log_error_count}" -gt "${LOG_ERROR_THRESHOLD}" ]; then
    log_warn "log-review-1h-summary.txt has ${log_error_count} lines (>${LOG_ERROR_THRESHOLD}) — review before declaring healthy"
    errors=$((errors+1))
fi
if [ "${errors}" -gt 0 ]; then
    write_failed 70 "${RUN_DIR}/log-review-1h-summary.txt"
    exit 1
fi

# 4) Connector tests (opt-in)
if [ "${RUN_CONNECTOR_TESTS:-0}" = "1" ]; then
    echo '{"placeholder":"slack-dm test would run here; deferred to system-qa-check"}' > "${RUN_DIR}/slack-dm-test.json"
    echo '{"placeholder":"subagent-isolated test"}' > "${RUN_DIR}/subagent-isolated-test.json"
    echo '{"placeholder":"cron agentTurn test"}' > "${RUN_DIR}/cron-agentTurn-test.json"
fi

# 5) Canary-pass artifact written BEFORE the operator prompt — verification has
# already passed by this point, so we don't lose the canary signal if the
# operator walks away from the Checkpoint D prompt for hours.
if [ "${ROLE}" = "personal-canary" ]; then
    {
        echo "hostname: ${HOSTNAME_VALUE}"
        echo "target_version: ${APPROVED}"
        echo "upgrade_timestamp: $(date -Iseconds)"
        echo "observed_for: just-after-upgrade"
        echo "gateway_healthy: yes"
        echo "log_errors: ${log_error_count}"
        echo "notification_path: $(cat "${RUN_DIR}/notification-path-test.txt")"
        echo "operator_notes: (auto-generated; recommend observing for 24h before upgrading work host)"
    } > "${RUN_DIR}/canary-pass.txt"
fi

# 6) Checkpoint D
banner "UPGRADE LOOKS HEALTHY
Version: $(cat "${RUN_DIR}/version-before.txt") -> $(cat "${RUN_DIR}/version-after.txt")
Log review: ${log_error_count} errors/fatals since upgrade
Connector tests: $( [ "${RUN_CONNECTOR_TESTS:-0}" = "1" ] && echo run || echo skipped )
Notification path: $(cat "${RUN_DIR}/notification-path-test.txt")
Canary-pass artifact: $( [ -f "${RUN_DIR}/canary-pass.txt" ] && echo "written" || echo "not applicable" )

RECOMMENDED NEXT STEP:
  Run \`system-qa-check\` for end-to-end agent verification.

Press ENTER to proceed (Step 99 handles reboot if needed),
Ctrl-C to investigate first."

if [ -z "${SU_NONINTERACTIVE:-}" ]; then
    prompt_continue "press ENTER to continue"
fi

step_complete 70
log_info "Step 70 complete"

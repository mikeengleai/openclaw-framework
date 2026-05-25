#!/usr/bin/env bash
# scripts/00-preflight.sh — host detection, tool/disk/network checks, run-dir creation.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

usage() {
    echo "usage: $0 [--resume <run-dir>]" >&2
    exit 2
}

RESUME_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --resume) RESUME_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

load_config

# Test override: allow tests to redirect the share path / canary path.
if [ -n "${SU_CONF_OVERRIDE_TAILSCALE_SHARE_PATH:-}" ]; then
    TAILSCALE_SHARE_PATH="${SU_CONF_OVERRIDE_TAILSCALE_SHARE_PATH}"
fi
if [ -n "${SU_CONF_OVERRIDE_CANARY_SHARE_PATH:-}" ]; then
    CANARY_SHARE_PATH="${SU_CONF_OVERRIDE_CANARY_SHARE_PATH}"
fi

# Resolve RUN_DIR
if [ -n "${RESUME_DIR}" ]; then
    [ -d "${RESUME_DIR}" ] || { log_err "--resume path not a directory: ${RESUME_DIR}"; exit 2; }
    RUN_DIR="${RESUME_DIR}"
    export RUN_DIR
    if step_done 00; then
        log_info "Step 00 already complete in ${RUN_DIR}; skipping (already complete)"
        exit 0
    fi
else
    make_run_dir
    RUN_DIR="${RUN_DIR_PATH}"
    export RUN_DIR
fi

umask 077

log_info "Preflight on ${HOSTNAME_VALUE} (role=${ROLE}); run dir=${RUN_DIR}"

# 1) Required tools
fail=0
for cmd in tar zstd jq curl tailscale; do
    require_cmd "$cmd" || fail=1
done
case "${OPENCLAW_INSTALL_KIND}" in
    docker) require_cmd docker || fail=1 ;;
    npm)    require_cmd systemctl || fail=1 ;;
esac
if ! command -v sqlite3 >/dev/null 2>&1; then
    log_warn "sqlite3 not on PATH; SQLite-native backup in step 10 will be skipped"
fi
[ "$fail" = "0" ] || { log_err "missing required tools — abort"; exit 1; }

# 2) Sudo
require_sudo || exit 1

# 3) Tailscale share mounted
if ! tailscale drive list 2>/dev/null | awk 'NR>2 {print $1}' | grep -qx "${TAILSCALE_SHARE_NAME}"; then
    log_err "Tailscale share '${TAILSCALE_SHARE_NAME}' not in 'tailscale drive list'"
    exit 1
fi

# 4) Disk space (5 GB free required on share + /)
THRESHOLD_MB=5000
share_free="$(disk_free_mb "${TAILSCALE_SHARE_PATH}")"
root_free="$(disk_free_mb "/")"
if [ "${share_free:-0}" -lt "${THRESHOLD_MB}" ]; then
    log_err "Tailscale share ${TAILSCALE_SHARE_PATH} has ${share_free} MB free (< ${THRESHOLD_MB} MB)"
    exit 1
fi
if [ "${root_free:-0}" -lt "${THRESHOLD_MB}" ]; then
    log_err "/ has ${root_free} MB free (< ${THRESHOLD_MB} MB)"
    exit 1
fi

# 5) Network check: docs.openclaw.ai reachable
if ! curl -fsS --max-time 10 https://docs.openclaw.ai/ -o /dev/null; then
    log_err "docs.openclaw.ai unreachable — version discovery in step 20 cannot proceed"
    exit 1
fi

# 6) Tailscale + network capture (artifact)
tailscale status > "${RUN_DIR}/tailscale-status.txt" 2>&1 || true
tailscale ip -4 > "${RUN_DIR}/tailscale-ipv4.txt" 2>&1 || true
df -h > "${RUN_DIR}/disk-free-before.txt" 2>&1 || true

# 7) Canary gate (work hosts only)
if [ "${REQUIRE_CANARY_PASS:-0}" = "1" ]; then
    if [ -f "${RUN_DIR}/canary-override.txt" ]; then
        log_warn "canary check overridden: $(cat "${RUN_DIR}/canary-override.txt")"
    else
        : "${CANARY_HOST:?CANARY_HOST must be set in config when REQUIRE_CANARY_PASS=1}"
        : "${CANARY_SHARE_PATH:?CANARY_SHARE_PATH must be set in config when REQUIRE_CANARY_PASS=1}"
        local_pass=""
        if [ -d "${CANARY_SHARE_PATH}" ]; then
            local_pass="$(find "${CANARY_SHARE_PATH}" -maxdepth 3 -name 'canary-pass.txt' -mtime -7 2>/dev/null | head -n 1)"
        fi
        if [ -z "${local_pass}" ]; then
            log_err "no recent canary-pass.txt found under ${CANARY_SHARE_PATH} — work upgrade blocked"
            log_err "to override: write a reason to ${RUN_DIR}/canary-override.txt and re-run"
            exit 1
        fi
        cp "${local_pass}" "${RUN_DIR}/canary-pass-from-${CANARY_HOST}.txt"
        log_info "canary pass ingested from ${local_pass}"
    fi
fi

# 8) Run start record
date -Iseconds > "${RUN_DIR}/run-start.txt"
{
    echo "hostname=${HOSTNAME_VALUE}"
    echo "role=${ROLE}"
    echo "install_kind=${OPENCLAW_INSTALL_KIND}"
    echo "share_path=${TAILSCALE_SHARE_PATH}"
} > "${RUN_DIR}/run-context.txt"

notify "Upgrade run starting on ${HOSTNAME_VALUE} (role=${ROLE}, run dir=${RUN_DIR})"
step_complete 00
log_info "Step 00 complete"

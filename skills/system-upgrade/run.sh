#!/usr/bin/env bash
# skill/run.sh — orchestrator for the system-upgrade skill.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS_DIR="${SU_SCRIPTS_DIR_OVERRIDE:-${SCRIPT_DIR}/scripts}"

usage() {
    cat <<EOF >&2
usage: $0 [--resume <run-dir>]
  --resume <run-dir>  Resume an interrupted run from the given directory.
EOF
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

ORDERED=(
    00-preflight
    10-backup-files
    20-version-discover
    30-recon
    40-pre-upgrade-snapshot
    50-apt-upgrade
    60-openclaw-upgrade
    70-post-upgrade-verify
    99-reboot
)

if [ -n "${RESUME_DIR}" ]; then
    [ -d "${RESUME_DIR}" ] || { echo "--resume path not a directory: ${RESUME_DIR}" >&2; exit 2; }
    export RUN_DIR="${RESUME_DIR}"
else
    # 00-preflight creates the run dir; capture it.
    "${SCRIPTS_DIR}/00-preflight.sh" || { echo "00-preflight failed" >&2; exit 1; }
    if [ -z "${RUN_DIR:-}" ]; then
        # Recover the freshly created run dir via the latest-upgrade symlink.
        # The host config tells us where TAILSCALE_SHARE_PATH is.
        # shellcheck source=lib/common.sh
        . "${SCRIPT_DIR}/lib/common.sh"
        load_config
        # Honor the test override if present (mirrors 00-preflight.sh behaviour).
        if [ -n "${SU_CONF_OVERRIDE_TAILSCALE_SHARE_PATH:-}" ]; then
            TAILSCALE_SHARE_PATH="${SU_CONF_OVERRIDE_TAILSCALE_SHARE_PATH}"
        fi
        link="${TAILSCALE_SHARE_PATH}/latest-upgrade"
        [ -L "${link}" ] || { echo "could not resolve RUN_DIR (no latest-upgrade symlink)" >&2; exit 1; }
        RUN_DIR="${TAILSCALE_SHARE_PATH}/$(readlink "${link}")"
        export RUN_DIR
    fi
fi

echo "[orchestrator] RUN_DIR=${RUN_DIR}"

for step in "${ORDERED[@]}"; do
    n="${step%%-*}"
    if [ -f "${RUN_DIR}/STEP-${n}.complete" ]; then
        echo "[orchestrator] skipping ${step} (already complete)"
        continue
    fi
    if [ "${step}" = "00-preflight" ] && [ -z "${RESUME_DIR}" ]; then
        # Already ran above; loop guard.
        continue
    fi
    echo "[orchestrator] running ${step}"
    # Forward --resume to 00-preflight when we're in resume mode so it doesn't
    # create a fresh run dir under env-set RUN_DIR. Other scripts read RUN_DIR
    # from the env directly.
    if [ "${step}" = "00-preflight" ] && [ -n "${RESUME_DIR}" ]; then
        if ! "${SCRIPTS_DIR}/${step}.sh" --resume "${RUN_DIR}"; then
            echo "[orchestrator] ${step} FAILED — see ${RUN_DIR}/FAILED-${n}.txt" >&2
            exit 1
        fi
    elif ! "${SCRIPTS_DIR}/${step}.sh"; then
        echo "[orchestrator] ${step} FAILED — see ${RUN_DIR}/FAILED-${n}.txt" >&2
        exit 1
    fi
done

echo "[orchestrator] all steps complete; RUN_DIR=${RUN_DIR}"

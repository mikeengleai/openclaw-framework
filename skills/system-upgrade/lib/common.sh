# skill/lib/common.sh — shared helpers for the system-upgrade skill.
# Source from any script: `source "$(dirname "$0")/../lib/common.sh"`.
# Environment overrides for tests: _SU_HOSTNAME_OVERRIDE replaces `hostname`.

set -o pipefail

# Resolve absolute path to the skill root (parent of lib/).
_SU_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILL_ROOT="$( cd "${_SU_LIB_DIR}/.." && pwd )"

_su_hostname() {
    if [ -n "${_SU_HOSTNAME_OVERRIDE:-}" ]; then
        echo "${_SU_HOSTNAME_OVERRIDE}"
    else
        hostname
    fi
}

log_info()  { printf '[%s] [INFO]  %s\n' "$(date -Iseconds)" "$*"; }
log_warn()  { printf '[%s] [WARN]  %s\n' "$(date -Iseconds)" "$*" >&2; }
log_err()   { printf '[%s] [ERROR] %s\n' "$(date -Iseconds)" "$*" >&2; }

banner() {
    local msg="$*"
    local width=72
    printf '%s\n' "$(printf '=%.0s' $(seq 1 $width))"
    printf '%s\n' "${msg}"
    printf '%s\n' "$(printf '=%.0s' $(seq 1 $width))"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_err "required command not found on PATH: ${cmd}"
        return 1
    fi
}

require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_err "passwordless sudo required (run 'sudo -v' first or configure NOPASSWD)"
        return 1
    fi
}

# Load the per-host config file from skill/config/<hostname>.conf.
# Validates HOSTNAME_EXPECTED matches.
load_config() {
    local host
    host="$(_su_hostname)"
    local conf="${SKILL_ROOT}/config/${host}.conf"
    if [ ! -f "${conf}" ]; then
        log_err "no config for host: ${host} (looked in ${conf})"
        return 1
    fi
    # shellcheck disable=SC1090
    if ! source "${conf}"; then
        log_err "config file failed to parse: ${conf}"
        return 1
    fi
    if [ "${HOSTNAME_EXPECTED:-}" != "${host}" ]; then
        log_err "config mismatch: HOSTNAME_EXPECTED=${HOSTNAME_EXPECTED:-<unset>} but hostname=${host}"
        return 1
    fi
    local required=(HOSTNAME_EXPECTED ROLE EMBARGO_HOURS TAILSCALE_SHARE_PATH TAILSCALE_SHARE_NAME OPENCLAW_INSTALL_KIND NTFY_TOPIC SLACK_CHANNEL)
    local k
    for k in "${required[@]}"; do
        if [ -z "${!k+set}" ]; then
            log_err "config missing required key: ${k} (in ${conf})"
            return 1
        fi
    done
    HOSTNAME_VALUE="${host}"
    export HOSTNAME_VALUE
}

# Create the run directory and update the latest-upgrade symlink.
# Sets RUN_DIR_PATH on success.
make_run_dir() {
    : "${TAILSCALE_SHARE_PATH:?TAILSCALE_SHARE_PATH must be set (call load_config first)}"
    : "${HOSTNAME_VALUE:?HOSTNAME_VALUE must be set (call load_config first)}"
    local ts
    ts="$(date +%Y-%m-%d-%H%M%S)"
    RUN_DIR_PATH="${TAILSCALE_SHARE_PATH}/upgrade-${HOSTNAME_VALUE}-${ts}"
    mkdir -p "${RUN_DIR_PATH}"
    chmod 700 "${RUN_DIR_PATH}"
    # Atomically replaces the existing latest-upgrade symlink (ln -sfn).
    local link="${TAILSCALE_SHARE_PATH}/latest-upgrade"
    ln -sfn "$(basename "${RUN_DIR_PATH}")" "${link}"
    export RUN_DIR_PATH
}

# Sentinel file helpers. Caller must have RUN_DIR set.
step_complete() {
    : "${RUN_DIR:?RUN_DIR must be set}"
    local n="$1"
    printf '%s\n' "$(date -Iseconds)" > "${RUN_DIR}/STEP-${n}.complete"
}

step_done() {
    : "${RUN_DIR:?RUN_DIR must be set}"
    local n="$1"
    [ -f "${RUN_DIR}/STEP-${n}.complete" ]
}

# Disk-free helper, returns MB as integer on stdout.
disk_free_mb() {
    local path="$1"
    df -BM --output=avail "$path" 2>/dev/null | tail -n 1 | tr -d ' M'
}

# Print a checkpoint banner and wait for ENTER.
prompt_continue() {
    local msg="$1"
    banner "${msg}"
    # shellcheck disable=SC2162
    read -r _ || return 1
}

# Write a FAILED-NN.txt with the last N lines of a log file (default 50).
write_failed() {
    : "${RUN_DIR:?RUN_DIR must be set}"
    local n="$1"
    local logfile="$2"
    local lines="${3:-50}"
    {
        printf 'FAILED at step %s\n' "${n}"
        printf 'timestamp: %s\n' "$(date -Iseconds)"
        printf -- '----- last %s lines of %s -----\n' "${lines}" "${logfile}"
        if [ -f "${logfile}" ]; then
            tail -n "${lines}" "${logfile}"
        else
            printf '(log file not present: %s)\n' "${logfile}"
        fi
    } > "${RUN_DIR}/FAILED-${n}.txt"
}

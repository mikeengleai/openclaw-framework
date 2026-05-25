#!/usr/bin/env bash
# scripts/99-reboot.sh — pre-reboot capture, install one-shot post-reboot notifier, reboot.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILL_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set}"
if step_done 99; then log_info "Step 99 already complete; skipping"; exit 0; fi

# 1) Pre-reboot capture
systemctl --failed --no-pager > "${RUN_DIR}/systemctl-failed-before-reboot.txt" 2>&1 || true
systemctl --user --failed --no-pager > "${RUN_DIR}/user-systemctl-failed-before-reboot.txt" 2>&1 || true

REBOOT=0
if [ -f "${RUN_DIR}/reboot-required.flag" ]; then REBOOT=1; fi
# Heuristic: kernel/libc seen in apt-upgrade.log
if grep -aE 'linux-image|libc6' "${RUN_DIR}/apt-upgrade.log" >/dev/null 2>&1; then REBOOT=1; fi

before="$(cat "${RUN_DIR}/version-before.txt" 2>/dev/null || echo unknown)"
after="$(cat "${RUN_DIR}/version-after.txt" 2>/dev/null || echo unknown)"

if [ "${REBOOT}" -eq 1 ]; then
    banner "REBOOT REQUIRED
Press ENTER to reboot now, or Ctrl-C to defer.
Post-reboot the one-shot notifier will capture state and notify."

    if [ -z "${SU_NONINTERACTIVE:-}" ] && [ -z "${SU_NO_REBOOT_TEST_MODE:-}" ]; then
        prompt_continue "press ENTER to reboot"
    fi

    # Install post-reboot one-shot unit
    UNIT_DIR="${HOME}/.config/systemd/user"
    mkdir -p "${UNIT_DIR}"
    sed \
        -e "s|__RUN_DIR__|${RUN_DIR}|g" \
        -e "s|__SKILL_ROOT__|${SKILL_ROOT}|g" \
        "${SKILL_ROOT}/lib/post-reboot-unit.template" \
        > "${UNIT_DIR}/openclaw-upgrade-complete-notify.service"

    # Skip systemctl daemon-reload + enable in test mode (no real user-systemd
    # available in CI; the test asserts on the unit file having been written).
    if [ -z "${SU_NO_REBOOT_TEST_MODE:-}" ]; then
        systemctl --user daemon-reload
        systemctl --user enable openclaw-upgrade-complete-notify.service
        log_info "post-reboot notifier installed and enabled"
    else
        log_info "[test mode] skipping systemctl --user daemon-reload + enable"
    fi

    if [ -z "${SU_NO_REBOOT_TEST_MODE:-}" ]; then
        sudo reboot
    else
        log_info "[test mode] skipping sudo reboot"
        # Mark step complete in test mode so the test can verify behavior
        step_complete 99
        date -Iseconds > "${RUN_DIR}/run-end.txt"
    fi
else
    notify "Upgrade complete on ${HOSTNAME_VALUE}: ${before} -> ${after}, no reboot needed, all checks passed"
    step_complete 99
    date -Iseconds > "${RUN_DIR}/run-end.txt"
fi
log_info "Step 99 complete"

#!/usr/bin/env bash
# Runs once after the post-upgrade reboot via a user-systemd one-shot.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILL_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
# shellcheck source=../lib/common.sh
. "${SKILL_ROOT}/lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SKILL_ROOT}/lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set in the systemd unit Environment=}"

uptime > "${RUN_DIR}/uptime-after-reboot.txt" 2>&1 || true
systemctl --failed --no-pager > "${RUN_DIR}/systemctl-failed-after-reboot.txt" 2>&1 || true
systemctl --user --failed --no-pager > "${RUN_DIR}/user-systemctl-failed-after-reboot.txt" 2>&1 || true

case "${OPENCLAW_INSTALL_KIND}" in
    npm)    timeout 30 openclaw doctor --json > "${RUN_DIR}/doctor-after-reboot.json" 2>&1 || true
            timeout 30 openclaw status > "${RUN_DIR}/status-after-reboot.txt" 2>&1 || true ;;
    docker) timeout 30 docker exec "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" openclaw doctor --json > "${RUN_DIR}/doctor-after-reboot.json" 2>&1 || true
            timeout 30 docker exec "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" openclaw status > "${RUN_DIR}/status-after-reboot.txt" 2>&1 || true ;;
esac

before="$(cat "${RUN_DIR}/version-before.txt" 2>/dev/null || echo unknown)"
after="$(cat "${RUN_DIR}/version-after.txt" 2>/dev/null || echo unknown)"
notify "Upgrade complete on ${HOSTNAME_VALUE}: ${before} -> ${after}, kernel $(uname -r), all checks passed"

step_complete 99
date -Iseconds > "${RUN_DIR}/run-end.txt"

# Self-cleanup: `systemctl --user disable --now <self>` deadlocks because systemd
# waits for *us* to exit while we wait for the disable to return. Use plain
# `disable` (no --now) and remove the unit file; systemd will reap us on exit.
systemctl --user disable openclaw-upgrade-complete-notify.service 2>/dev/null || true
rm -f "${HOME}/.config/systemd/user/openclaw-upgrade-complete-notify.service"
systemctl --user daemon-reload 2>/dev/null || true

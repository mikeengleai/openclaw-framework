#!/usr/bin/env bash
# scripts/50-apt-upgrade.sh — apt update/upgrade with simulation + risky-package gate.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set}"
if step_done 50; then log_info "Step 50 already complete; skipping"; exit 0; fi

# 1) Before state
apt-mark showmanual > "${RUN_DIR}/apt-manual-before.txt" 2>/dev/null || true
apt-mark showhold > "${RUN_DIR}/apt-holds-before.txt" 2>/dev/null || true
dpkg --get-selections > "${RUN_DIR}/dpkg-selections-before.txt" 2>/dev/null || true
sudo cp -a /etc/apt "${RUN_DIR}/etc-apt-backup" 2>/dev/null || true

# 2) Update + simulate
sudo apt update > "${RUN_DIR}/apt-update.log" 2>&1
sudo apt list --upgradable > "${RUN_DIR}/apt-upgradable.txt" 2>/dev/null || true
sudo apt-get -s upgrade > "${RUN_DIR}/apt-upgrade-simulated.txt" 2>/dev/null || true

# 3) Risky-package detection
RISKY_REGEX='\b(nodejs|npm|docker|docker-ce|containerd|runc|systemd|openssh-server|tailscale|nginx|caddy|python3|sqlite3|libsqlite3|libc6|linux-image|linux-headers)\b'
grep -aiE "${RISKY_REGEX}" "${RUN_DIR}/apt-upgrade-simulated.txt" > "${RUN_DIR}/apt-risky-packages.txt" || true

# 4) Checkpoint C
if [ -s "${RUN_DIR}/apt-risky-packages.txt" ]; then
    if [ -z "${SU_NONINTERACTIVE:-}" ]; then
        banner "RISKY PACKAGE CHANGES DETECTED — see apt-risky-packages.txt:"
        cat "${RUN_DIR}/apt-risky-packages.txt"
        echo
        echo "These affect runtime, networking, containerization, daemon behavior, or DB handling."
        echo "Acknowledge by writing a one-line reason to ${RUN_DIR}/apt-approval.txt, then re-run."
    fi
    if [ ! -f "${RUN_DIR}/apt-approval.txt" ]; then
        log_err "apt-approval.txt required: ${RUN_DIR}/apt-approval.txt"
        exit 1
    fi
fi

if [ -z "${SU_NONINTERACTIVE:-}" ]; then
    prompt_continue "Press ENTER to apply apt upgrades, or Ctrl-C to abort"
fi

# 5) Apply
sudo apt upgrade -y > "${RUN_DIR}/apt-upgrade.log" 2>&1

# 6) After state + diffs
apt-mark showmanual > "${RUN_DIR}/apt-manual-after.txt" 2>/dev/null || true
apt-mark showhold > "${RUN_DIR}/apt-holds-after.txt" 2>/dev/null || true
dpkg --get-selections > "${RUN_DIR}/dpkg-selections-after.txt" 2>/dev/null || true
dpkg -l > "${RUN_DIR}/dpkg-list-after.txt" 2>/dev/null || true
diff -u "${RUN_DIR}/apt-manual-before.txt" "${RUN_DIR}/apt-manual-after.txt" > "${RUN_DIR}/apt-manual-diff.txt" || true
diff -u "${RUN_DIR}/dpkg-selections-before.txt" "${RUN_DIR}/dpkg-selections-after.txt" > "${RUN_DIR}/dpkg-selections-diff.txt" || true

# 7) Reboot detection
if [ -f /var/run/reboot-required ]; then
    : > "${RUN_DIR}/reboot-required.flag"
    log_info "reboot required (deferred until step 99)"
fi

# 8) Node major-version gate
node -v > "${RUN_DIR}/node-version-after-apt.txt" 2>&1 || true
before_major="$(awk -F. '{gsub(/^v/,"",$1); print $1}' "${RUN_DIR}/node-version-before.txt" 2>/dev/null || echo "")"
after_major="$(awk -F. '{gsub(/^v/,"",$1); print $1}' "${RUN_DIR}/node-version-after-apt.txt" 2>/dev/null || echo "")"
if [ -n "${before_major}" ] && [ -n "${after_major}" ] && [ "${before_major}" != "${after_major}" ]; then
    : > "${RUN_DIR}/node-major-changed.flag"
    log_warn "Node major changed: ${before_major}.x -> ${after_major}.x — verify gateway after upgrade"
fi

reboot_msg="no"; [ -f "${RUN_DIR}/reboot-required.flag" ] && reboot_msg="yes"
risky_msg="no";  [ -s "${RUN_DIR}/apt-risky-packages.txt" ] && risky_msg="yes"
notify "apt upgrade complete on ${HOSTNAME_VALUE} (reboot required: ${reboot_msg}, risky packages: ${risky_msg})"
step_complete 50
log_info "Step 50 complete"

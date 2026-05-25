#!/usr/bin/env bash
# scripts/10-backup-files.sh — file-level backup with SQLite-native handling.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set (orchestrator passes it via env)}"

if step_done 10; then
    log_info "Step 10 already complete; skipping"
    exit 0
fi

umask 077
TS="$(date +%Y%m%d-%H%M%S)"
MAIN_TARBALL="${RUN_DIR}/openclaw-backup-${HOSTNAME_VALUE}-${TS}.tar.zst"
ETC_TARBALL="${RUN_DIR}/etc-backup-${HOSTNAME_VALUE}-${TS}.tar.zst"

# 1) SQLite-native backup
mkdir -p "${RUN_DIR}/sqlite-backups"
SQLITE_LIST="${RUN_DIR}/sqlite-files.txt"
SQLITE_LOG="${RUN_DIR}/sqlite-backup.log"
: > "${SQLITE_LOG}"

if command -v sqlite3 >/dev/null 2>&1; then
    find "${HOME}/.openclaw" "${HOME}/workspaces" -type f \
        \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' -o -name '*.qmd' \) \
        2>/dev/null > "${SQLITE_LIST}" || true
    while IFS= read -r db; do
        [ -f "$db" ] || continue
        safe="$(printf '%s' "$db" | sed 's#^/##; s#[/ ]#_#g')"
        if sqlite3 "$db" ".backup '${RUN_DIR}/sqlite-backups/${safe}.backup.sqlite'" >> "${SQLITE_LOG}" 2>&1; then
            echo "ok ${db}" >> "${SQLITE_LOG}"
        else
            echo "FAILED ${db}" >> "${SQLITE_LOG}"
        fi
    done < "${SQLITE_LIST}"
    SQLITE_STATUS="ok"
else
    SQLITE_STATUS="skipped_sqlite3_missing"
    echo "sqlite3 not on PATH; skipping SQLite-native backup" >> "${SQLITE_LOG}"
fi

# 2) Docker config snapshot (englebert1 only) — must happen before the main tarball
if [ "${OPENCLAW_INSTALL_KIND}" = "docker" ] && [ -z "${SU_SKIP_DOCKER_EXTRAS:-}" ]; then
    DCSNAP="${RUN_DIR}/docker-config-snapshot"
    mkdir -p "${DCSNAP}"
    sudo cp "${OPENCLAW_DOCKER_COMPOSE}" "${DCSNAP}/docker-compose.yml"
    if sudo test -f "$(dirname "${OPENCLAW_DOCKER_COMPOSE}")/.env"; then
        sudo cp "$(dirname "${OPENCLAW_DOCKER_COMPOSE}")/.env" "${DCSNAP}/.env"
    fi
    sudo chown -R "$(id -u):$(id -g)" "${DCSNAP}"
    chmod 600 "${DCSNAP}"/* 2>/dev/null || true
fi

# 3) Main tarball
MAIN_INCLUDES=()
[ -d "${HOME}/.openclaw" ] && MAIN_INCLUDES+=("${HOME}/.openclaw")
[ -d "${HOME}/.claude" ]   && MAIN_INCLUDES+=("${HOME}/.claude")
[ -f "${HOME}/CLAUDE.md" ] && MAIN_INCLUDES+=("${HOME}/CLAUDE.md")
[ -d "${HOME}/workspaces" ] && MAIN_INCLUDES+=("${HOME}/workspaces")
[ -d "${HOME}/.config/systemd/user" ] && MAIN_INCLUDES+=("${HOME}/.config/systemd/user")
[ -d "${HOME}/bin" ] && MAIN_INCLUDES+=("${HOME}/bin")
for f in "${HOME}/.gitconfig" "${HOME}/.tmux.conf" "${HOME}/.bashrc" "${HOME}/.profile"; do
    [ -f "$f" ] && MAIN_INCLUDES+=("$f")
done
if [ "${OPENCLAW_INSTALL_KIND}" = "npm" ] && [ -f "${HOME}/.npm-global/lib/node_modules/openclaw/package.json" ]; then
    MAIN_INCLUDES+=("${HOME}/.npm-global/lib/node_modules/openclaw/package.json")
fi
if [ -d "${RUN_DIR}/sqlite-backups" ]; then
    MAIN_INCLUDES+=("${RUN_DIR}/sqlite-backups")
fi
if [ -d "${RUN_DIR}/docker-config-snapshot" ]; then
    MAIN_INCLUDES+=("${RUN_DIR}/docker-config-snapshot")
fi

tar --use-compress-program='zstd -T0' \
    --exclude='*/.openclaw/venv' \
    --exclude='*/.openclaw/logs' \
    --exclude='*/.claude/cache' \
    --exclude='*/.claude/paste-cache' \
    --exclude='*/.claude/file-history' \
    -cf "${MAIN_TARBALL}" "${MAIN_INCLUDES[@]}" 2> "${RUN_DIR}/tar-main.stderr" || {
        log_err "main tarball creation failed"
        write_failed 10 "${RUN_DIR}/tar-main.stderr"
        notify "Backup FAILED on ${HOSTNAME_VALUE} — see ${RUN_DIR}/FAILED-10.txt"
        exit 1
    }
chmod 600 "${MAIN_TARBALL}"

# 4) /etc tarball (sudo)
if [ -z "${SU_SKIP_ETC_BACKUP:-}" ]; then
    ETC_PATHS=(
        /etc/systemd/system /etc/systemd/user
        /etc/nginx /etc/caddy /etc/apache2
        /etc/cron.d /etc/crontab /etc/sudoers.d
        /etc/docker/daemon.json
        /etc/apt/sources.list /etc/apt/sources.list.d /etc/apt/preferences.d
        /etc/hosts /etc/ssh/sshd_config /etc/environment /etc/profile.d
    )
    EXISTING=()
    for p in "${ETC_PATHS[@]}"; do
        [ -e "$p" ] && EXISTING+=("$p")
    done
    if [ "${#EXISTING[@]}" -gt 0 ]; then
        sudo tar --use-compress-program='zstd -T0' \
            --warning=no-file-ignored \
            -cf "${ETC_TARBALL}" "${EXISTING[@]}" 2> "${RUN_DIR}/tar-etc.stderr" || \
            log_warn "/etc tarball had warnings (see tar-etc.stderr)"
        sudo chown "$(id -u):$(id -g)" "${ETC_TARBALL}"
        chmod 600 "${ETC_TARBALL}"
    fi
fi

# 5) Restore-test (listing + spot-extract; no checksums)
if ! tar --list --use-compress-program=unzstd -f "${MAIN_TARBALL}" > "${RUN_DIR}/tarball-file-list.txt" 2> "${RUN_DIR}/tar-list.stderr"; then
    log_err "main tarball is unreadable — abort"
    write_failed 10 "${RUN_DIR}/tar-list.stderr"
    exit 1
fi
mkdir -p "${RUN_DIR}/restore-test"
tar -xf "${MAIN_TARBALL}" --use-compress-program=unzstd -C "${RUN_DIR}/restore-test" \
    --wildcards '*/CLAUDE.md' '*/.gitconfig' 2> "${RUN_DIR}/restore-test.stderr" || true

# 6) Manifest companions
{
    echo "timestamp=$(date -Iseconds)"
    echo "hostname=${HOSTNAME_VALUE}"
    echo "os=$( . /etc/os-release && echo "${PRETTY_NAME}" )"
    echo "kernel=$(uname -r)"
    echo "install_kind=${OPENCLAW_INSTALL_KIND}"
    echo "main_tarball=$(basename "${MAIN_TARBALL}")"
    echo "main_tarball_size=$(stat -c %s "${MAIN_TARBALL}" 2>/dev/null || echo 0)"
    echo "main_tarball_files=$(wc -l < "${RUN_DIR}/tarball-file-list.txt")"
    if [ -f "${ETC_TARBALL}" ]; then
        echo "etc_tarball=$(basename "${ETC_TARBALL}")"
        echo "etc_tarball_size=$(stat -c %s "${ETC_TARBALL}")"
    fi
    echo "sqlite_native_backup=${SQLITE_STATUS}"
    if [ "${SQLITE_STATUS}" != "ok" ] && [ "${ROLE}" = "work" ]; then
        echo "requires_manual_approval=yes  # SQLite-native backup unavailable on work host"
    fi
} > "${RUN_DIR}/MANIFEST.txt"

[ -x "${HOME}/.openclaw/venv/bin/pip" ] && "${HOME}/.openclaw/venv/bin/pip" freeze > "${RUN_DIR}/pip-freeze.txt" 2>/dev/null || true
dpkg -l > "${RUN_DIR}/dpkg-list.txt" 2>/dev/null || true
npm -g ls --depth=0 > "${RUN_DIR}/npm-global-list.txt" 2>/dev/null || true
{ crontab -l 2>/dev/null; echo "---"; systemctl --user list-timers 2>/dev/null; } > "${RUN_DIR}/crontab.txt" || true
du -sh "${HOME}/.openclaw" "${HOME}/.claude" "${HOME}/workspaces" 2>/dev/null > "${RUN_DIR}/backup-source-sizes.txt" || true

size_h="$(du -h "${MAIN_TARBALL}" | cut -f1)"
notify "Backup complete on ${HOSTNAME_VALUE}: $(basename "${MAIN_TARBALL}") (${size_h}). Copy to your laptop before continuing."
step_complete 10
log_info "Step 10 complete"

# skill/lib/notify.sh — ntfy + Slack wrapper.
# Reads NTFY_TOPIC and SLACK_CHANNEL from the sourced host config.

# shellcheck source=common.sh
. "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/common.sh"

# notify <message>
# Sends to ntfy (if NTFY_TOPIC is set and `ntfy` is on PATH) and Slack via
# `openclaw message send` (if SLACK_CHANNEL is set and `openclaw` is on PATH).
# Best-effort: failures are logged but never propagated.
notify() {
    local msg="$*"
    if [ -n "${NTFY_TOPIC:-}" ] && command -v ntfy >/dev/null 2>&1; then
        ntfy pub "${NTFY_TOPIC}" "${msg}" >/dev/null 2>&1 \
            || log_warn "ntfy publish failed (topic=${NTFY_TOPIC})"
    fi
    if [ -n "${SLACK_CHANNEL:-}" ] && command -v openclaw >/dev/null 2>&1; then
        openclaw message send --channel slack --target "${SLACK_CHANNEL}" -m "${msg}" >/dev/null 2>&1 \
            || log_warn "slack publish failed (channel=${SLACK_CHANNEL})"
    fi
    return 0
}

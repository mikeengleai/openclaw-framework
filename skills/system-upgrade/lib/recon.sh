# skill/lib/recon.sh — wrappers around external search skills.
# Tests override _recon_perplexity / _recon_brave / _recon_github via SU_RECON_BACKEND.

# shellcheck source=common.sh
. "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/common.sh"

_recon_perplexity() {
    local query="$1"
    if [ -n "${SU_RECON_BACKEND_DIR:-}" ] && [ -x "${SU_RECON_BACKEND_DIR}/openclaw-perplexity" ]; then
        "${SU_RECON_BACKEND_DIR}/openclaw-perplexity" --query "${query}"
    else
        openclaw skill run perplexity --query "${query}" 2>/dev/null || echo '{"error":"perplexity skill unavailable"}'
    fi
}

_recon_brave() {
    local query="$1"
    if [ -n "${SU_RECON_BACKEND_DIR:-}" ] && [ -x "${SU_RECON_BACKEND_DIR}/openclaw-brave" ]; then
        "${SU_RECON_BACKEND_DIR}/openclaw-brave" --query "${query}"
    else
        openclaw skill run brave --query "${query}" 2>/dev/null || echo '{"error":"brave skill unavailable"}'
    fi
}

_recon_github() {
    local version="$1"
    if command -v gh >/dev/null 2>&1; then
        gh issue list --repo openclaw/openclaw --search "${version}" --state all --limit 20 --json number,title,state,url,createdAt 2>/dev/null \
            || echo '[]'
    else
        echo '[]'
    fi
}

# Blocker keywords: regex (case-insensitive).
_RECON_BLOCKER_REGEX='broken|regression|rollback|downgrade|crash|fails|failed install|gateway won.?t start|slack wrong thread|slack no response|cron skipped|ghost cron|memory lost|auth broken|channel delivery|docker crashloop|runtime deps|database migration'

# Run blocker scan over recon JSON files; print each match line prefixed with the source basename.
# Always returns 0; a non-matching grep is not an error.
recon_scan_blockers() {
    local file
    for file in "$@"; do
        [ -f "$file" ] || continue
        # shellcheck disable=SC2002
        cat "$file" | grep -aiE "${_RECON_BLOCKER_REGEX}" | sed "s|^|$(basename "$file"): |" || true
    done
    return 0
}

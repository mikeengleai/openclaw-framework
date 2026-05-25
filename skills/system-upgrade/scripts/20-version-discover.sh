#!/usr/bin/env bash
# scripts/20-version-discover.sh — current version + docs + GitHub + embargo filter.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set}"
if step_done 20; then log_info "Step 20 already complete; skipping"; exit 0; fi

# 1) Current version
case "${OPENCLAW_INSTALL_KIND}" in
    npm)
        version_raw="$(openclaw --version 2>/dev/null || echo "OpenClaw unknown")"
        ;;
    docker)
        if [ -n "${SU_SKIP_DOCKER_EXEC:-}" ]; then
            version_raw="${MOCK_OPENCLAW_VERSION:-OpenClaw unknown}"
        else
            version_raw="$(docker exec "${OPENCLAW_DOCKER_GATEWAY_CONTAINER}" openclaw --version 2>/dev/null || echo "OpenClaw unknown")"
        fi
        ;;
esac
# Extract just "X.Y.Z(-N)?"
echo "${version_raw}" | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+(-[0-9]+)?' | head -n 1 > "${RUN_DIR}/version-current.txt" \
    || echo "unknown" > "${RUN_DIR}/version-current.txt"

# 2) update-check.json (best-effort copy)
if [ -f "${HOME}/.openclaw/update-check.json" ]; then
    cp "${HOME}/.openclaw/update-check.json" "${RUN_DIR}/update-check.json"
fi

# 3) docs.openclaw.ai latest stable
curl -fsS https://docs.openclaw.ai/install/updating > "${RUN_DIR}/docs-install-updating.html" 2>/dev/null || true
grep -oE '[Oo]pen[Cc]law\s+v?[0-9]{4}\.[0-9]+\.[0-9]+(-[0-9]+)?' "${RUN_DIR}/docs-install-updating.html" 2>/dev/null \
    | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+(-[0-9]+)?' \
    | head -n 1 > "${RUN_DIR}/docs-openclaw-latest.txt" || true

# 4) GitHub releases — prefer gh, fall back to curl on api.github.com
if command -v gh >/dev/null 2>&1; then
    gh release list openclaw/openclaw --limit 10 --json tagName,publishedAt,isPrerelease,name,body \
        > "${RUN_DIR}/releases.json" 2>/dev/null || true
fi
if [ ! -s "${RUN_DIR}/releases.json" ]; then
    curl -fsS 'https://api.github.com/repos/openclaw/openclaw/releases?per_page=10' \
        > "${RUN_DIR}/releases.json" 2>/dev/null || echo "[]" > "${RUN_DIR}/releases.json"
fi

# Normalize: ensure each entry has `tagName`, `publishedAt`, `isPrerelease`. The api.github.com
# response uses `tag_name`, `published_at`, `prerelease` — translate if needed.
jq '
  if type=="array" then
    map(if .tagName == null then
          {tagName: .tag_name, publishedAt: .published_at, isPrerelease: .prerelease, name: .name, body: .body}
        else .
        end)
  else .
  end
' "${RUN_DIR}/releases.json" > "${RUN_DIR}/releases-normalized.json"
mv "${RUN_DIR}/releases-normalized.json" "${RUN_DIR}/releases.json"

# 5) Embargo filter
NOW_EPOCH="$(date +%s)"
EMBARGO_SECS=$(( EMBARGO_HOURS * 3600 ))

jq --argjson now "${NOW_EPOCH}" --argjson embargo "${EMBARGO_SECS}" '
  [ .[] |
    select(.isPrerelease == false) |
    . + {age_seconds: ($now - (.publishedAt | fromdateiso8601))} |
    select(.age_seconds >= $embargo) |
    . + {version: (.tagName | sub("^openclaw@v";"") | sub("^v";""))} ] |
  sort_by(.publishedAt) | reverse | .[0:3]
' "${RUN_DIR}/releases.json" > "${RUN_DIR}/candidates.json"

step_complete 20
log_info "Step 20 complete: $(jq 'length' "${RUN_DIR}/candidates.json") candidates after embargo"

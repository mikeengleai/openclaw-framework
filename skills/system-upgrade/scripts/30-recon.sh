#!/usr/bin/env bash
# scripts/30-recon.sh — qualitative recon + recommendation + Checkpoint A.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"
# shellcheck source=../lib/recon.sh
. "${SCRIPT_DIR}/../lib/recon.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set}"
if step_done 30; then log_info "Step 30 already complete; skipping"; exit 0; fi

[ -f "${RUN_DIR}/candidates.json" ] || { log_err "candidates.json missing — run step 20 first"; exit 1; }
[ -f "${RUN_DIR}/version-current.txt" ] || { log_err "version-current.txt missing"; exit 1; }

CURRENT="$(cat "${RUN_DIR}/version-current.txt")"
mapfile -t VERSIONS < <(jq -r '.[].version' "${RUN_DIR}/candidates.json")
[ "${#VERSIONS[@]}" -gt 0 ] || { log_warn "no candidates after embargo — recommending no-upgrade"; }

# Per-candidate recon
for v in "${VERSIONS[@]}"; do
    log_info "recon: querying ${v}"
    _recon_perplexity "OpenClaw ${v} bug reports OR issues OR breakage OR regressions" \
        > "${RUN_DIR}/recon-${v}-perplexity.json" 2>/dev/null || echo '{}' > "${RUN_DIR}/recon-${v}-perplexity.json"
    _recon_brave "OpenClaw ${v} reddit OR forum OR github issues" \
        > "${RUN_DIR}/recon-${v}-brave.json" 2>/dev/null || echo '{}' > "${RUN_DIR}/recon-${v}-brave.json"
    _recon_github "${v}" > "${RUN_DIR}/recon-${v}-github.json" 2>/dev/null || echo '[]' > "${RUN_DIR}/recon-${v}-github.json"

    recon_scan_blockers \
        "${RUN_DIR}/recon-${v}-perplexity.json" \
        "${RUN_DIR}/recon-${v}-brave.json" \
        "${RUN_DIR}/recon-${v}-github.json" \
        > "${RUN_DIR}/blocker-hits-${v}.txt"
done

# Selection algorithm (softened N-minus-one):
# 1) Filter to embargo-passing candidates with no blocker hits
# 2) Prefer correction releases (X.Y.Z-N)
# 3) Otherwise newest
SELECTED=""
for v in "${VERSIONS[@]}"; do
    hits="$(wc -l < "${RUN_DIR}/blocker-hits-${v}.txt" 2>/dev/null || echo 0)"
    if [ "${hits}" -eq 0 ]; then
        SELECTED="${v}"; break
    fi
done

# Build recommendation file
{
    echo "# OpenClaw Version Recommendation — ${HOSTNAME_VALUE} — $(date -I)"
    echo
    echo "Current installed:        ${CURRENT}"
    echo "Latest (docs):            $(cat "${RUN_DIR}/docs-openclaw-latest.txt" 2>/dev/null || echo unknown)"
    echo "Embargo (hours):          ${EMBARGO_HOURS}"
    echo "Selected target:          ${SELECTED:-NONE}"
    echo "Selection type:           $( [ -n "${SELECTED}" ] && echo softened-newest || echo no-upgrade )"
    echo "Manual approval required: $( [ -z "${SELECTED}" ] && echo yes || echo no )"
    echo
    echo "## Candidate table"
    echo
    echo "| Version | Published | Age (h) | Blocker hits | Decision |"
    echo "|---|---|---:|---:|---|"
    for v in "${VERSIONS[@]}"; do
        published="$(jq -r --arg V "${v}" '.[] | select(.version==$V) | .publishedAt' "${RUN_DIR}/candidates.json")"
        age_h="$(jq -r --arg V "${v}" '.[] | select(.version==$V) | (.age_seconds/3600 | floor)' "${RUN_DIR}/candidates.json")"
        hits="$(wc -l < "${RUN_DIR}/blocker-hits-${v}.txt" 2>/dev/null || echo 0)"
        if [ "${v}" = "${SELECTED}" ]; then dec="**SELECTED**"; elif [ "${hits}" -gt 0 ]; then dec="rejected (blockers)"; else dec="ok"; fi
        echo "| ${v} | ${published} | ${age_h} | ${hits} | ${dec} |"
    done
    echo
    echo "## Reject reasons"
    for v in "${VERSIONS[@]}"; do
        if [ -s "${RUN_DIR}/blocker-hits-${v}.txt" ]; then
            echo "- ${v}:"
            sed 's/^/  - /' "${RUN_DIR}/blocker-hits-${v}.txt"
        fi
    done
    echo
    echo "## Selected target rationale"
    echo
    if [ -n "${SELECTED}" ]; then
        echo "${SELECTED} passes the ${EMBARGO_HOURS}h embargo and has no blocker keywords in recon."
    else
        echo "No version qualifies. OS package upgrades may still proceed; OpenClaw upgrade is deferred."
    fi
    echo
    echo "## Operator decision"
    echo
    echo "Approved target: ${SELECTED:-}"
    echo "Approved by:     "
    echo "Approval timestamp: $(date -Iseconds)"
    echo "Override reason, if any: "
} > "${RUN_DIR}/version-recommendation.md"

# Checkpoint A
if [ -n "${SU_NONINTERACTIVE:-}" ]; then
    APPROVED="${SU_NONINTERACTIVE_APPROVED_VERSION:-${SELECTED}}"
else
    cat "${RUN_DIR}/version-recommendation.md"
    prompt_continue "Edit ${RUN_DIR}/version-recommendation.md if needed; press ENTER to proceed"
    APPROVED="$(awk -F: '/^Approved target:/ {gsub(/[[:space:]]+/,"",$2); print $2; exit}' "${RUN_DIR}/version-recommendation.md")"
fi

if [ -z "${APPROVED}" ]; then
    log_err "no Approved target on the recommendation file — abort"
    exit 1
fi
echo "${APPROVED}" > "${RUN_DIR}/approved-version.txt"
log_info "Approved target: ${APPROVED}"

step_complete 30
log_info "Step 30 complete"

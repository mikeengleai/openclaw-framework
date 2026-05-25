#!/usr/bin/env bash
# scripts/60-openclaw-upgrade.sh — apply the OpenClaw upgrade and confirm /healthz.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/notify.sh
. "${SCRIPT_DIR}/../lib/notify.sh"

load_config
: "${RUN_DIR:?RUN_DIR must be set}"
if step_done 60; then log_info "Step 60 already complete; skipping"; exit 0; fi

[ -f "${RUN_DIR}/approved-version.txt" ] || { log_err "approved-version.txt missing"; exit 1; }
APPROVED="$(cat "${RUN_DIR}/approved-version.txt")"

LOG="${RUN_DIR}/openclaw-update.log"

case "${OPENCLAW_INSTALL_KIND}" in
    npm)
        log_info "npm: openclaw update --tag ${APPROVED}"
        if ! openclaw update --tag "${APPROVED}" > "${LOG}" 2>&1; then
            write_failed 60 "${LOG}"
            notify "OpenClaw upgrade FAILED on ${HOSTNAME_VALUE} (npm) — see ${RUN_DIR}/FAILED-60.txt"
            exit 1
        fi
        ;;
    docker)
        # Try to pin the image to the approved version. Strategy: parse the
        # current OPENCLAW_IMAGE from the compose .env (may be a registry path
        # like "openclaw/openclaw:latest"), substitute its tag with the approved
        # version, and probe `docker pull <pinned>`. If the pinned tag exists,
        # update the .env so `docker compose up -d` recreates against it. If
        # the pinned tag does not exist, fall back to the existing tag and
        # warn the operator (the recon step already approved the version, so
        # absent pinning we just take whatever the registry currently serves).
        env_file="$(dirname "${OPENCLAW_DOCKER_COMPOSE}")/.env"
        current_image=""
        pinned_image=""
        if sudo test -f "${env_file}"; then
            current_image="$(sudo grep -E '^OPENCLAW_IMAGE=' "${env_file}" | tail -n 1 | cut -d= -f2- | tr -d '"' || true)"
        fi
        # Skip pinning if image is the local build tag (no registry).
        if [ -n "${current_image}" ] && [[ "${current_image}" != *":local" ]] && [[ "${current_image}" == *":"* ]]; then
            pinned_image="${current_image%:*}:${APPROVED}"
            log_info "docker: probing for pinned image ${pinned_image}"
            if sudo docker pull "${pinned_image}" > "${LOG}" 2>&1; then
                log_info "docker: pinned image found; updating ${env_file}"
                sudo sed -i.bak-pre-upgrade -E "s|^OPENCLAW_IMAGE=.*|OPENCLAW_IMAGE=${pinned_image}|" "${env_file}"
                echo "pinned_image=${pinned_image}" > "${RUN_DIR}/docker-pinned-image.txt"
            else
                log_warn "docker: pinned image ${pinned_image} not in registry — using ${current_image}"
                echo "pinned_image=NOT_AVAILABLE" > "${RUN_DIR}/docker-pinned-image.txt"
                echo "fallback_image=${current_image}" >> "${RUN_DIR}/docker-pinned-image.txt"
            fi
        else
            log_info "docker: skipping image pinning (current=${current_image:-unset}, looks local-only)"
            echo "pinned_image=SKIPPED_LOCAL_BUILD" > "${RUN_DIR}/docker-pinned-image.txt"
        fi

        log_info "docker: pulling and recreating gateway"
        {
            sudo docker compose -f "${OPENCLAW_DOCKER_COMPOSE}" pull openclaw-gateway
            sudo docker compose -f "${OPENCLAW_DOCKER_COMPOSE}" up -d openclaw-gateway
        } >> "${LOG}" 2>&1 || {
            write_failed 60 "${LOG}"
            notify "OpenClaw upgrade FAILED on ${HOSTNAME_VALUE} (docker) — see ${RUN_DIR}/FAILED-60.txt"
            exit 1
        }
        ;;
    *)
        log_err "unknown OPENCLAW_INSTALL_KIND=${OPENCLAW_INSTALL_KIND}"
        exit 1
        ;;
esac

# Wait for /healthz
TIMEOUT="${SU_HEALTHZ_TIMEOUT_SECS:-90}"
HEALTHZ_URL="${SU_HEALTHZ_URL:-http://127.0.0.1:18789/healthz}"
log_info "waiting up to ${TIMEOUT}s for ${HEALTHZ_URL}"
deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "${deadline}" ]; do
    if curl -fsS --max-time 3 "${HEALTHZ_URL}" >/dev/null 2>&1; then
        log_info "/healthz OK"
        notify "OpenClaw upgraded on ${HOSTNAME_VALUE}: ${APPROVED} (gateway healthy)"
        step_complete 60
        log_info "Step 60 complete"
        exit 0
    fi
    sleep 1
done

log_err "/healthz did not return 200 within ${TIMEOUT}s"
write_failed 60 "${LOG}"
notify "OpenClaw upgrade health check FAILED on ${HOSTNAME_VALUE} — gateway not responding on /healthz"
exit 1

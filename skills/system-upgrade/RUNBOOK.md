# system-upgrade RUNBOOK

This is the human-readable, step-by-step procedure for the system-upgrade skill.
Run via `run.sh` (which executes the scripts in order); read this file before/during the run for context, checkpoints, and rollback paths.

## Roll-out order

1. **englebert1** first (canary).
2. Observe ≥ 24h.
3. **1klaw** second (work).

## Per-step summary

### Step 00 — Preflight
Verifies host config, required tools, sudo, Tailscale share mount, ≥ 5 GB free on share and /, docs.openclaw.ai reachable, and (1klaw only) a recent canary-pass.txt exists. Creates `${SHARE}/upgrade-${HOST}-${TS}/`.

### Step 10 — File-level backup
- SQLite-native backup of every `*.sqlite|*.sqlite3|*.db|*.qmd` under `~/.openclaw` and `~/workspaces` via `sqlite3 .backup`.
- Main tarball: `~/.openclaw`, `~/.claude`, `~/CLAUDE.md`, `~/workspaces`, `~/.config/systemd/user`, `~/bin`, dotfiles. Excludes venv/, logs/, claude caches.
- Separate `/etc` tarball (sudo).
- Restore-test: `tar --list` + spot-extract `*/CLAUDE.md`.
- Manifest companions: pip-freeze, dpkg-list, npm-global-list, crontab, sizes.
- **Operator action: copy the main tarball to your laptop before continuing.** No SHA-256 verification by design; the listing test confirms readability.

### Step 20 — Version discovery
Captures `version-current.txt`, fetches `docs.openclaw.ai/install/updating`, lists GitHub releases, applies the host-specific embargo (72h englebert1 / 96h 1klaw) to produce `candidates.json`.

### Step 30 — Recon + Checkpoint A
For each candidate version: Perplexity, Brave, GitHub issues. Blocker keyword scan. Selection: newest embargo-passing version with no blocker hits (correction releases preferred when present). Operator reviews `version-recommendation.md` and presses ENTER to approve.

### Step 40 — Pre-upgrade snapshot + Checkpoint B
Captures baseline (version, doctor, status, secrets-audit, dry-run, env), Node/npm versions, Docker rendered compose + container/image inspect + `docker save` rollback artifact (englebert1 only). Quiesces hermes (englebert1) or per-host service list (1klaw) during the snapshot prompt. Operator triggers Hostinger snapshot via web panel and presses ENTER. Writes `hostinger-snapshot-confirmation.md`. Restores quiesced services.

### Step 50 — apt + Checkpoint C
`apt update` + simulation + risky-package detection (Node/Docker/systemd/OpenSSH/Tailscale/libc/kernel/SQLite). If risky packages present, operator must write a one-line approval to `${RUN_DIR}/apt-approval.txt`. `apt upgrade -y`. Diff before/after. Detect reboot requirement and Node major version change.

### Step 60 — OpenClaw upgrade
- **npm:** `openclaw update --tag <approved-version>` — the binary handles npm reinstall, plugin sync, completion refresh, and gateway restart.
- **docker:** `docker compose pull openclaw-gateway && up -d openclaw-gateway`.
- Both wait up to 90s for `/healthz` 200. Failure writes `FAILED-60.txt` and points at the rollback paths below.

### Step 70 — Post-upgrade verification + Checkpoint D
After-state artifacts; pass criteria: version match, /healthz, log error threshold, notification path. On englebert1, writes `canary-pass.txt`. Operator presses ENTER to continue.

### Step 99 — Reboot + Checkpoint E
`systemctl --failed` capture. If reboot needed, install one-shot user-systemd unit `openclaw-upgrade-complete-notify.service`, then `sudo reboot`. Post-reboot the unit captures uptime and post-reboot state, fires final notification, disables itself.

## Rollback paths

**Whole-server (any host):** restore Hostinger snapshot via web panel.

**OpenClaw-only (1klaw / npm):**
```bash
npm i -g openclaw@<prior-version>
systemctl --user restart openclaw-gateway
```
Prior version is in `${RUN_DIR}/version-before.txt` and the package layout is in the file-level backup.

**OpenClaw-only (englebert1 / docker):**
```bash
unzstd -c ${RUN_DIR}/openclaw-local-image-before.tar.zst | sudo docker load
sudo docker compose -f /root/openclaw/docker-compose.yml up -d openclaw-gateway
```

## Resuming an interrupted run

```bash
run.sh --resume /home/openclaw/<share>/upgrade-<host>-<ts>/
```
Skips any step where `STEP-NN.complete` exists. Force a step to re-run by deleting its sentinel.

## Hand-off to system-qa-check

After Checkpoint D the runbook recommends running the sibling `system-qa-check` skill for end-to-end agent verification. That skill is independent and has its own brainstorm/spec.

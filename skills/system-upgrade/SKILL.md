---
name: system-upgrade
description: Repeatable, checkpoint-driven OS + OpenClaw upgrade for englebert1 (canary, Docker) and 1klaw (work, npm). Backs up, snapshots, upgrades, verifies. Hands off to system-qa-check for deep verification.
allowed-tools: Read, Bash
argument-hint: '[--resume <run-dir>]'
---

# system-upgrade

Run an end-to-end OS + OpenClaw upgrade with operator checkpoints.

## Roll-out order (mandatory unless overridden)

1. **englebert1** first (personal/canary).
2. Observe at least 24h.
3. **1klaw** second (work). The work run reads `canary-pass.txt` from the canary host's Tailscale share and aborts if missing/old (override with `${RUN_DIR}/canary-override.txt`).

## Quick start

```bash
# Fresh run on this host:
~/.openclaw/skills/system-upgrade/run.sh

# Resume an interrupted run:
~/.openclaw/skills/system-upgrade/run.sh --resume /home/openclaw/<share>/upgrade-<host>-<ts>/
```

## What it does (high level)

| Step | What | Checkpoint |
|---|---|---|
| 00 | Preflight: tools, disk, network, canary gate | — |
| 10 | File backup (SQLite-native + main + /etc tarballs); restore-test | — |
| 20 | Version discovery (current, docs.openclaw.ai, GitHub releases, embargo) | — |
| 30 | Recon (Perplexity/Brave/GitHub) + recommendation file | **A** — operator approves target |
| 40 | Baseline + Docker save + quiesce | **B** — operator confirms Hostinger snapshot |
| 50 | apt update + simulate + apply | **C** — operator approves risky packages |
| 60 | OpenClaw upgrade (npm or docker) + /healthz wait | — |
| 70 | Post-upgrade verification + canary-pass.txt | **D** — operator confirms healthy |
| 99 | Pre-reboot capture; install post-reboot one-shot; reboot | **E** — operator approves reboot |

## See also

- Spec: `~/workspaces/system-updater/docs/superpowers/specs/2026-05-02-system-upgrade-design.md`
- Runbook (human-readable, step-by-step): `RUNBOOK.md` (next to this file)
- Sibling skill (deeper QA): `system-qa-check` (separate brainstorm/spec)

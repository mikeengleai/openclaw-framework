# OpenClaw Framework

Everything you need to stand up and operate a self-hosted AI agent server built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

This repo contains the scripts, skills, configuration examples, and documentation used to run a production [OpenClaw](https://openclaw.ai) deployment across two servers. Use it as a starting kit for your own build, or fork it and make it yours.

## What's in the box

| Directory | What it is |
|---|---|
| `bin/` | **Claude Workspaces** (`cw`) — workspace manager for isolated Claude sessions, context rotation, memory compaction, and handoffs |
| `skills/system-map/` | **Daily system map** — Python collector that snapshots your entire system (agents, skills, cron, memory, security, Tailscale) to a single markdown file |
| `skills/system-upgrade/` | **System upgrade** — 10 checkpointed bash scripts for safe, rollback-capable OS and OpenClaw upgrades |
| `guide/` | **Companion build guide** — 14-section step-by-step guide from Tailscale account creation to troubleshooting |
| `server-maps/` | **Example server map** — a real production system map snapshot so you can see what the output looks like |
| `examples/cron/` | **Cron job templates** — sample scheduled jobs (daily system map, daily backup) |
| `examples/agents/` | **Agent config examples** — model provider configuration with placeholder API keys |

## Quick start

### Prerequisites

1. A server — Mac Mini at home, or a VPS from [Hostinger](https://hostinger.com) ($10-30/mo), Ubuntu
2. A [Tailscale](https://tailscale.com) account (free tier covers 100 devices)
3. An [Anthropic API key](https://console.anthropic.com)

### Install

```bash
# Log in as root on your server

# 1. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 2. Install Claude Code
npm install -g @anthropic-ai/claude-code

# 3. Log in to your Claude account
claude login

# 4. Clone this repo
git clone https://github.com/mikeengleai/openclaw-framework.git
cd openclaw-framework

# 5. Set up the workspace manager
cp bin/claude-workspaces ~/bin/claude-workspaces
chmod +x ~/bin/claude-workspaces
ln -s ~/bin/claude-workspaces ~/bin/cw
cp bin/compaction-prompt.md ~/bin/compaction-prompt.md

# 6. Create your workspaces directory
mkdir -p ~/workspaces

# 7. Launch the workspace manager
cw
```

## Components

### Claude Workspaces (`bin/claude-workspaces`)

Workspace manager for Claude Code sessions. Each workspace is a topic-scoped directory with its own memory and session history.

- **Launch/resume** workspaces in tmux, direct shell, or background (agent view)
- **Rotate** sessions when context gets long: compact memory, generate handoff, archive, fresh launch
- **Memory compaction** with LLM-driven curation (dedup, tighten, remove stale entries)
- **Handoff generation** produces structured HANDOFF.md for seamless session transitions
- **Archive management** with restore and purge

```bash
cw                        # Interactive menu
cw launch myproject       # Launch a workspace
cw rotate myproject       # Full rotation: compact + handoff + archive + fresh
cw archive list           # See archived sessions
```

### Daily System Map (`skills/system-map/`)

A Python script that generates a comprehensive markdown snapshot of your entire system. Runs daily via cron.

Covers: infrastructure, agents (configs, models, bindings), skills, cron jobs, memory files, security rules, plugins, Tailscale nodes, scripts, and more.

```bash
python3 skills/system-map/scripts/system_map.py
```

### System Upgrade (`skills/system-upgrade/`)

10 checkpointed bash scripts for safe server upgrades. Each script can run independently and be rolled back.

```
00-preflight.sh          → Pre-flight checks
10-backup-files.sh       → Back up critical files
20-version-discover.sh   → Check available versions
30-recon.sh              → System reconnaissance
40-pre-upgrade-snapshot.sh → Hostinger snapshot + quiesce
50-apt-upgrade.sh        → OS package upgrades
60-openclaw-upgrade.sh   → OpenClaw upgrade
70-post-upgrade-verify.sh → Post-upgrade verification
99-reboot.sh             → Safe reboot with notification
post-reboot-notify.sh    → Confirm services came back up
```

Includes per-host configuration files and a detailed RUNBOOK.

### Companion Build Guide (`guide/companion-guide.md`)

14-section implementation guide covering:

1. Create a Tailscale account
2. Sign up for a VPS
3. Lock down the Linux server
4. Install Node.js, Python, SQLite, tmux
5. Install OpenClaw
6. Configure your first agent
7. Set up QMD memory
8. Set up the browsing service
9. Connect Slack
10. Schedule your first cron job
11. Set up ntfy.sh push notifications
12. Map a Tailscale shared drive
13. The `cw` workflow
14. Troubleshooting

## Resources

- **Presentation deck:** [openclaw-deck-9tm.pages.dev](https://openclaw-deck-9tm.pages.dev)
- **OpenClaw:** [openclaw.ai](https://openclaw.ai)
- **Claude Code:** [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code)

## License

Apache 2.0. See [LICENSE](LICENSE).

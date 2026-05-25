---
name: system-map
description: Generate a comprehensive markdown mapping of the entire OpenClaw system configuration — all agents, skills, bindings, cron jobs, memory architecture, MCP servers, plugins, security settings, and infrastructure. Saves output with server name and timestamp to the Tailscale shared folder.
allowed-tools: Bash(python3:*), Bash(hostname:*), Bash(date:*), Bash(mkdir:*), Read, Glob, Grep
user-invocable: true
argument-hint: ""
---

# System Map — Full Configuration Export

Generate a structured markdown document capturing the complete OpenClaw system state.

## Quick Run (recommended)

The Python collector gathers all data in one pass and writes the output file directly:

```bash
python3 ~/.openclaw/skills/system-map/scripts/system_map.py
```

This produces a timestamped markdown file and prints the output path. It is the preferred method — fast, deterministic, and avoids LLM timeout issues.

### Options

```bash
# Write to stdout instead of file (for piping or review)
python3 ~/.openclaw/skills/system-map/scripts/system_map.py --stdout

# Custom output directory
python3 ~/.openclaw/skills/system-map/scripts/system_map.py --output-dir /tmp

# JSON output (machine-readable)
python3 ~/.openclaw/skills/system-map/scripts/system_map.py --json
```

## Output File Naming & Location

The filename MUST include the server name and generation timestamp:

```
openclaw-system-map_<hostname>_<YYYYMMDD-HHMMSS>.md
```

Example: `openclaw-system-map_englebert1_20260426-143022.md`

**Save location priority:**
1. **`~/shared/`** — Tailscale shared folder (englebert1 convention)
2. **`~/tailscale-shared/`** — Alternate Tailscale shared folder (other servers)
3. **Fallback** — `~/` with a warning

## What to Capture

Scan the following sources and compile a single markdown document with all sections below.

### Source Files

| Source | Path | What to Extract |
|--------|------|-----------------|
| Main config | `~/.openclaw/openclaw.json` | agents, bindings, skills, channels, gateway, memory, models, browser, auth |
| Cron jobs | `~/.openclaw/cron/jobs.json` | All scheduled jobs with schedule, agent, status, delivery config |
| Agent dirs | `~/.openclaw/agents/*/` | List of all agent directories |
| Skill dirs | `~/.openclaw/skills/*/` | List of all skills with key files |
| Shared refs | `~/.openclaw/references/` | Reference documents |
| Shared content | `~/.openclaw/shared/` | Shared content rules |
| Memory store | `~/.openclaw/memory/` | Memory backend (SQLite) |
| Workspace dirs | `~/.openclaw/workspace-*/` | Per-agent workspace contents |
| Claude Code settings | `~/.claude/settings.json`, `~/.claude/settings.local.json` | Permissions model |
| Claude Code plugins | `~/.claude/plugins/marketplaces/` | Active plugins, hooks |
| Claude Code project memory | `~/.claude/projects/-home-openclaw/memory/` | Project memory files |
| MCP servers | `~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/` | Configured MCP integrations |
| Host crontab | `crontab -l` | Host-level scheduled tasks |
| Systemd services | `systemctl --user list-units` | User-level services |
| Network | `ip addr`, `ss -tlnp`, `tailscale status` | Interfaces, ports, tailnet |

### Output Sections

The markdown document MUST include all of the following sections:

1. **Architecture Overview** — Platform summary, models, communication bus, gateway, memory backend
2. **Infrastructure** — Hardware (CPU, RAM, disk), kernel, network interfaces, listening ports
3. **Tailscale Network** — All tailnet nodes, funnel config, shared directory
4. **Docker / Containers** — Running containers, network mode, images
5. **System Services** — Ollama, LiteLLM, VNC, and other host/user services
6. **OpenClaw Gateway** — Port, mode, auth, rate limits, node ID
7. **Agents** — Table of all agents with: name, primary model, profile, status, emoji, Slack channel, subagent access. Include subagent dependency graph if applicable.
8. **Subagent Limits** — maxConcurrent, maxSpawnDepth, maxChildrenPerAgent, timeouts
9. **Channel Bindings** — All route bindings mapping Slack channels and Telegram to agents
10. **Skills** — Table of all skills with: name, directory, description, key files. Note which are in `skills.entries` vs directory-only.
11. **Cron Jobs** — Table of all jobs (OpenClaw cron + host crontab) with: ID, agent, schedule, timezone, description, status
12. **Memory Architecture** — QMD config (hybrid weights, MMR, temporal decay), Claude Code project memory files, per-agent memory
13. **Shared References** — All files in references/ and shared/
14. **External Integrations** — MCP servers, auth profiles, model aliases
15. **Plugins** — Active plugins, custom plugins, hook triggers
16. **Hooks & Transforms** — Runtime shield, Gmail hook, custom transforms
17. **Claude Code Configuration** — Settings, permissions, plugins
18. **Scripts & Utilities** — Contents of ~/bin/
19. **Security & Permissions** — Gateway security, Slack access control, SSH, exec approvals
20. **Key Counts Summary** — Total counts for agents, skills, bindings, cron jobs, MCP servers, plugins, hooks, memory files
21. **Known Issues** — Error states, disabled jobs, offline nodes, blocklists

## Output Format

- Use GitHub-flavored markdown with tables
- Include the server hostname and generation timestamp at the top
- Use code blocks for dependency graphs
- Mark error states clearly in cron job status
- Redact secrets (API keys, tokens) — show type/provider but not values
- Save using the naming convention and location priority described above
- Do NOT overwrite previous exports — each run produces a uniquely-timestamped file

## When to Use

- When you need a current snapshot of the full system for analysis or reporting
- Before making architectural changes to understand the current state
- For external tools that consume the system map as structured input
- When comparing current state against the baseline in project memory
- When comparing system configuration across multiple OpenClaw servers

#!/usr/bin/env python3
"""
system_map.py — OpenClaw System Map Generator

Collects comprehensive system configuration and outputs a structured
markdown document. Designed to run fast (no LLM calls) and produce
deterministic output suitable for cross-server comparison.
"""

import argparse
import datetime
import json
import os
import pathlib
import re
import socket
import subprocess
import sys

HOME = pathlib.Path.home()
OPENCLAW = HOME / ".openclaw"
CLAUDE = HOME / ".claude"

# Secret patterns to redact
SECRET_PATTERNS = [
    (re.compile(r'(sk-[a-zA-Z0-9_-]{20,})'), '[REDACTED_API_KEY]'),
    (re.compile(r'(xoxb-[a-zA-Z0-9-]+)'), '[REDACTED_SLACK_BOT]'),
    (re.compile(r'(xapp-[a-zA-Z0-9-]+)'), '[REDACTED_SLACK_APP]'),
    (re.compile(r'(xoxp-[a-zA-Z0-9-]+)'), '[REDACTED_SLACK_USER]'),
    (re.compile(r'([a-f0-9]{64})'), '[REDACTED_TOKEN_64]'),
    (re.compile(r'(ghp_[a-zA-Z0-9]{36,})'), '[REDACTED_GITHUB]'),
    (re.compile(r'(\d{10}:AA[a-zA-Z0-9_-]{33})'), '[REDACTED_TELEGRAM]'),
]


def redact(text):
    """Replace known secret patterns with redaction markers."""
    if not isinstance(text, str):
        return text
    for pattern, replacement in SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def run(cmd, timeout=10):
    """Run a shell command and return stdout, or empty string on failure."""
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ""


def read_json(path):
    """Read and parse a JSON file, return None on failure."""
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def read_text(path):
    """Read a text file, return empty string on failure."""
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""


def collect_hostname():
    return socket.gethostname()


def collect_infrastructure():
    """Collect hardware, kernel, disk, memory info."""
    data = {}
    data["hostname"] = collect_hostname()
    data["kernel"] = run("uname -r")
    data["arch"] = run("uname -m")
    data["uname"] = run("uname -a")

    # CPU
    cpuinfo = read_text("/proc/cpuinfo")
    model_names = re.findall(r"model name\s*:\s*(.+)", cpuinfo)
    data["cpu_model"] = model_names[0] if model_names else "unknown"
    data["cpu_count"] = len(model_names)

    # Memory
    meminfo = read_text("/proc/meminfo")
    for key in ["MemTotal", "MemAvailable"]:
        m = re.search(rf"{key}:\s+(\d+)\s+kB", meminfo)
        if m:
            data[key.lower()] = int(m.group(1))

    # Disk
    data["disk"] = run("df -h /home/openclaw --output=size,used,avail,pcent | tail -1")

    # Swap
    data["swap"] = run("free -h | grep Swap")

    return data


def collect_network():
    """Collect network interfaces and listening ports."""
    data = {}
    # IP addresses
    ip_lines = run("ip -4 addr show | grep inet")
    data["interfaces"] = []
    for line in ip_lines.splitlines():
        m = re.search(r"inet\s+(\S+)\s+.*\s+(\S+)$", line.strip())
        if m:
            data["interfaces"].append({"addr": m.group(1), "iface": m.group(2)})

    # Listening ports
    ss_out = run("ss -tlnp 2>/dev/null")
    data["ports"] = []
    for line in ss_out.splitlines()[1:]:  # skip header
        parts = line.split()
        if len(parts) >= 4:
            local = parts[3]
            process = parts[-1] if "users:" in parts[-1] else ""
            proc_name = ""
            m = re.search(r'"([^"]+)"', process)
            if m:
                proc_name = m.group(1)
            data["ports"].append({"local": local, "process": proc_name})

    return data


def collect_tailscale():
    """Collect tailscale status."""
    raw = run("tailscale status 2>/dev/null")
    data = {"nodes": [], "funnel": []}
    for line in raw.splitlines():
        if line.startswith("#"):
            if "Funnel" in line:
                data["funnel"].append(line.strip("# ").strip())
            continue
        parts = line.split()
        if len(parts) >= 4:
            data["nodes"].append({
                "ip": parts[0],
                "name": parts[1],
                "user": parts[2],
                "os": parts[3],
                "status": " ".join(parts[4:]) if len(parts) > 4 else "online",
            })
    return data


def collect_docker():
    """Collect running containers."""
    raw = run("docker ps --format '{{.ID}}|{{.Image}}|{{.Status}}|{{.Names}}' 2>/dev/null")
    containers = []
    for line in raw.splitlines():
        parts = line.split("|")
        if len(parts) == 4:
            containers.append({
                "id": parts[0], "image": parts[1],
                "status": parts[2], "name": parts[3],
            })
    return containers


def collect_openclaw_config():
    """Read and parse the main openclaw.json config."""
    return read_json(OPENCLAW / "openclaw.json")


def collect_agents(config):
    """Extract agent information from config and directories."""
    agents = []
    if config and "agents" in config:
        agent_defs = config.get("agents", {})
        defaults = agent_defs.get("defaults", {})
        default_model = defaults.get("model", {}).get("primary", "default")

        # Agents are in a 'list' array, not 'entries' dict
        agent_list = agent_defs.get("list", [])
        if isinstance(agent_list, list):
            for agent in agent_list:
                if not isinstance(agent, dict):
                    continue
                model_cfg = agent.get("model", {})
                agents.append({
                    "name": agent.get("id", agent.get("name", "unknown")),
                    "model": model_cfg.get("primary", default_model) if isinstance(model_cfg, dict) else str(model_cfg),
                    "profile": agent.get("tools", {}).get("profile", "full"),
                    "identity": agent.get("name", agent.get("id", "")),
                    "enabled": not agent.get("disabled", False),
                    "subagent_access": bool(agent.get("tools", {}).get("agentToAgent")),
                })

    # Also list agent directories
    agent_dirs = sorted(OPENCLAW.glob("agents/*/"))
    dir_names = [d.name for d in agent_dirs if d.is_dir()]

    return {"configured": agents, "directories": dir_names}


def collect_skills(config):
    """Extract skill information from config and directories."""
    registered = {}
    if config and "skills" in config:
        registered = config["skills"].get("entries", {})

    skill_dirs = sorted(OPENCLAW.glob("skills/*/"))
    skills = []
    for d in skill_dirs:
        if not d.is_dir() or d.name.startswith("."):
            continue
        skill_md = d / "SKILL.md"
        desc = ""
        if skill_md.exists():
            content = read_text(skill_md)
            # Extract description from frontmatter
            m = re.search(r"description:\s*(.+)", content)
            if m:
                desc = m.group(1).strip()

        scripts = sorted((d / "scripts").glob("*")) if (d / "scripts").exists() else []
        script_names = [s.name for s in scripts if s.is_file()]

        skills.append({
            "name": d.name,
            "registered": d.name in registered,
            "enabled": registered.get(d.name, {}).get("enabled", d.name in registered),
            "description": desc[:120] + "..." if len(desc) > 120 else desc,
            "scripts": script_names,
            "has_skill_md": skill_md.exists(),
        })

    return skills


def collect_channel_bindings(config):
    """Extract channel-to-agent bindings."""
    bindings = []
    if not config or "channels" not in config:
        return bindings

    channels_cfg = config["channels"]

    # Slack channels: channels.slack.channels.{id: config}
    slack = channels_cfg.get("slack", {})
    slack_channels = slack.get("channels", {})
    if isinstance(slack_channels, dict):
        for channel_id, ch_config in slack_channels.items():
            if not isinstance(ch_config, dict):
                continue
            bindings.append({
                "id": channel_id,
                "agent": ch_config.get("agent", "main"),
                "platform": "slack",
                "requireMention": ch_config.get("requireMention", True),
            })

    # Telegram channels
    telegram = channels_cfg.get("telegram", {})
    tg_channels = telegram.get("channels", telegram.get("entries", {}))
    if isinstance(tg_channels, dict):
        for channel_id, ch_config in tg_channels.items():
            if not isinstance(ch_config, dict):
                continue
            bindings.append({
                "id": channel_id,
                "agent": ch_config.get("agent", "main"),
                "platform": "telegram",
                "requireMention": ch_config.get("requireMention", True),
            })

    return bindings


def collect_cron_jobs():
    """Collect OpenClaw cron jobs and host crontab."""
    oc_cron = read_json(OPENCLAW / "cron" / "jobs.json")
    jobs = []

    # Handle {version, jobs: [...]} wrapper format
    job_list = []
    if isinstance(oc_cron, dict) and "jobs" in oc_cron:
        job_list = oc_cron["jobs"]
    elif isinstance(oc_cron, list):
        job_list = oc_cron

    for job in job_list:
        if not isinstance(job, dict):
            continue
        sched = job.get("schedule", {})
        if isinstance(sched, dict):
            sched_str = sched.get("expr", sched.get("at", str(sched)))
            tz = sched.get("tz", "UTC")
        else:
            sched_str = str(sched)
            tz = "UTC"
        jobs.append({
            "id": job.get("id", "")[:12],
            "name": job.get("name", "unnamed"),
            "schedule": sched_str,
            "timezone": tz,
            "agent": job.get("agentId", job.get("agent", "—")),
            "enabled": job.get("enabled", True),
            "status": "—",
            "source": "openclaw",
        })

    # Host crontab
    crontab = run("crontab -l 2>/dev/null")
    for line in crontab.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 5)
        if len(parts) >= 6:
            jobs.append({
                "id": "—",
                "name": parts[5][:60],
                "schedule": " ".join(parts[:5]),
                "timezone": "UTC",
                "agent": "—",
                "enabled": True,
                "status": "—",
                "source": "crontab",
            })

    return jobs


def collect_memory(config):
    """Collect memory architecture details."""
    data = {"qmd": {}, "project_memories": [], "memory_files": []}

    if config and "memory" in config:
        mem_cfg = config["memory"]
        data["qmd"] = {
            "backend": mem_cfg.get("backend", "unknown"),
            "provider": mem_cfg.get("provider", "unknown"),
            "search": mem_cfg.get("search", {}),
        }

    # Claude Code project memory
    mem_dir = CLAUDE / "projects" / "-home-openclaw" / "memory"
    if mem_dir.exists():
        for f in sorted(mem_dir.glob("*.md")):
            data["project_memories"].append(f.name)

    # OpenClaw memory store
    mem_store = OPENCLAW / "memory"
    if mem_store.exists():
        for f in sorted(mem_store.iterdir()):
            data["memory_files"].append({"name": f.name, "size": f.stat().st_size})

    return data


def collect_plugins(config):
    """Collect plugin information."""
    plugins = []
    if config and "plugins" in config:
        entries = config["plugins"].get("entries", config["plugins"])
        if isinstance(entries, dict):
            for name, pcfg in entries.items():
                if name in ("entries",):  # skip meta keys
                    continue
                if isinstance(pcfg, dict):
                    plugins.append({
                        "name": name,
                        "enabled": pcfg.get("enabled", True),
                    })
                else:
                    plugins.append({"name": name, "enabled": bool(pcfg)})

    # Custom plugins
    custom = []
    plugin_dir = OPENCLAW / "plugins"
    if plugin_dir.exists():
        for d in sorted(plugin_dir.iterdir()):
            if d.is_dir():
                files = [f.name for f in d.iterdir() if f.is_file()]
                custom.append({"name": d.name, "files": files})

    return {"registered": plugins, "custom": custom}


def collect_hooks():
    """Collect hook and transform information."""
    hooks = []
    hook_dir = OPENCLAW / "hooks"
    if hook_dir.exists():
        for d in sorted(hook_dir.iterdir()):
            if d.is_dir():
                files = [f.name for f in d.rglob("*") if f.is_file()]
                hooks.append({"name": d.name, "files": files})
    return hooks


def collect_gateway(config):
    """Extract gateway configuration."""
    if config and "gateway" in config:
        gw = config["gateway"]
        return {
            "port": gw.get("port"),
            "mode": gw.get("mode"),
            "bind": gw.get("bind"),
            "auth": gw.get("auth", {}).get("mode"),
            "tailscale": gw.get("tailscale"),
            "rateLimit": gw.get("rateLimit"),
        }
    return {}


def collect_node():
    """Read node.json."""
    return read_json(OPENCLAW / "node.json") or {}


def collect_claude_settings():
    """Collect Claude Code settings (redacted)."""
    settings = read_json(CLAUDE / "settings.json") or {}
    local = read_json(CLAUDE / "settings.local.json") or {}
    return {"settings": settings, "local_permissions": local}


def collect_scripts():
    """List scripts in ~/bin/."""
    bin_dir = HOME / "bin"
    scripts = []
    if bin_dir.exists():
        for f in sorted(bin_dir.iterdir()):
            if f.is_symlink():
                scripts.append({"name": f.name, "type": "symlink", "target": str(f.resolve())})
            elif f.is_file():
                scripts.append({"name": f.name, "type": "file", "size": f.stat().st_size})
    return scripts


def collect_services():
    """Collect host-level service info."""
    services = []

    # Check ollama
    ollama_status = run("systemctl is-active ollama 2>/dev/null")
    if ollama_status == "active":
        models = run("ollama list 2>/dev/null")
        services.append({"name": "ollama", "status": "active", "port": 11434, "models": models})

    # Check litellm
    litellm_status = run("systemctl is-active litellm 2>/dev/null")
    if litellm_status == "active":
        services.append({"name": "litellm", "status": "active", "port": 4100})

    # User services
    user_units = run("systemctl --user list-units --type=service --state=active --no-legend 2>/dev/null")
    for line in user_units.splitlines():
        parts = line.split()
        if parts:
            services.append({"name": parts[0], "status": "active", "port": None})

    return services


def collect_security(config):
    """Collect security-related configuration (redacted)."""
    data = {}

    # SSH keys
    ssh_dir = HOME / ".ssh"
    if ssh_dir.exists():
        data["ssh_keys"] = [f.name for f in ssh_dir.iterdir() if f.is_file()]

    # Exec approvals
    approvals = read_json(OPENCLAW / "exec-approvals.json")
    if approvals:
        data["exec_approvals"] = {"version": approvals.get("version"), "has_socket": bool(approvals.get("socket"))}

    # Gateway security
    if config and "gateway" in config:
        gw = config["gateway"]
        data["gateway_auth"] = gw.get("auth", {}).get("mode", "unknown")
        data["rate_limit"] = gw.get("rateLimit", {})

    # Slack access control
    if config and "slack" in config:
        slack = config["slack"]
        data["slack_allowed_users"] = len(slack.get("allowFrom", []))
        data["slack_dm_policy"] = slack.get("dm", {}).get("policy", "unknown")

    return data


def collect_mcp():
    """Collect MCP server configurations."""
    mcp_configs = []
    # Check common MCP config locations
    for path in [
        CLAUDE / "mcp.json",
        HOME / ".config" / "claude-code" / "mcp.json",
    ]:
        if path.exists():
            cfg = read_json(path)
            if cfg:
                mcp_configs.append({"path": str(path), "servers": list(cfg.get("mcpServers", {}).keys())})

    # Check plugin marketplace MCP
    marketplace = CLAUDE / "plugins" / "marketplaces" / "claude-plugins-official" / "external_plugins"
    if marketplace.exists():
        for f in marketplace.iterdir():
            if f.suffix == ".json":
                mcp_configs.append({"path": str(f), "servers": [f.stem]})

    return mcp_configs


# --- Rendering ---

def render_markdown(data):
    """Render collected data as a markdown system map."""
    hostname = data["infrastructure"]["hostname"]
    ts = data["timestamp"]
    lines = []

    def h1(t): lines.append(f"# {t}\n")
    def h2(t): lines.append(f"## {t}\n")
    def h3(t): lines.append(f"### {t}\n")
    def p(t): lines.append(f"{t}\n")
    def table(headers, rows):
        lines.append("| " + " | ".join(headers) + " |")
        lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
        for row in rows:
            lines.append("| " + " | ".join(str(c) for c in row) + " |")
        lines.append("")

    h1(f"OpenClaw System Map — {hostname}")
    p(f"**Generated**: {ts}")
    p(f"**Host**: {hostname}")
    if data.get("node", {}).get("nodeId"):
        p(f"**Node ID**: {data['node']['nodeId']}")
    p("")

    # --- 1. Architecture Overview ---
    h2("1. Architecture Overview")
    config = data.get("config") or {}
    agents_cfg = config.get("agents", {})
    defaults = agents_cfg.get("defaults", {})
    p(f"- **Primary Model**: {redact(defaults.get('model', {}).get('primary', 'N/A'))}")
    p(f"- **Fallback Model**: {redact(str(defaults.get('model', {}).get('fallbacks', ['N/A'])))}")
    p(f"- **Gateway**: port {data.get('gateway', {}).get('port', 'N/A')}, mode {data.get('gateway', {}).get('mode', 'N/A')}")
    mem = data.get("memory", {}).get("qmd", {})
    p(f"- **Memory Backend**: {mem.get('backend', 'N/A')}")
    p(f"- **Memory Provider**: {mem.get('provider', 'N/A')}")
    p("")

    # --- 2. Infrastructure ---
    h2("2. Infrastructure")
    infra = data["infrastructure"]
    table(["Property", "Value"], [
        ["Hostname", infra["hostname"]],
        ["Kernel", infra.get("uname", "N/A")],
        ["CPU", f"{infra.get('cpu_model', 'N/A')} ({infra.get('cpu_count', '?')} vCPU)"],
        ["RAM", f"{infra.get('memtotal', 0) // 1024} MB total, {infra.get('memavailable', 0) // 1024} MB available"],
        ["Disk", infra.get("disk", "N/A").strip()],
        ["Swap", infra.get("swap", "None").strip() or "None"],
    ])

    # --- 3. Tailscale Network ---
    h2("3. Tailscale Network")
    ts_data = data.get("tailscale", {})
    if ts_data.get("funnel"):
        for f_line in ts_data["funnel"]:
            p(f"**Funnel**: {f_line}")
    if ts_data.get("nodes"):
        table(["IP", "Name", "User", "OS", "Status"], [
            [n["ip"], n["name"], n["user"], n["os"], n.get("status", "")] for n in ts_data["nodes"]
        ])
    else:
        p("Tailscale not available or not running.")
    p("")

    # --- 4. Docker / Containers ---
    h2("4. Docker / Containers")
    containers = data.get("docker", [])
    if containers:
        table(["Container", "Image", "Status", "Name"], [
            [c["id"][:12], c["image"], c["status"], c["name"]] for c in containers
        ])
    else:
        p("No running containers.")
    p("")

    # --- 5. System Services ---
    h2("5. System Services")
    services = data.get("services", [])
    if services:
        table(["Service", "Status", "Port"], [
            [s["name"], s["status"], s.get("port") or "—"] for s in services
        ])
        # Ollama models
        for s in services:
            if s["name"] == "ollama" and s.get("models"):
                h3("Ollama Models")
                p(f"```\n{s['models']}\n```")
    else:
        p("No services detected.")
    p("")

    # --- 6. OpenClaw Gateway ---
    h2("6. OpenClaw Gateway")
    gw = data.get("gateway", {})
    if gw:
        table(["Setting", "Value"], [
            [k, redact(str(v))] for k, v in gw.items() if v is not None
        ])
    p("")

    # --- 7. Agents ---
    h2("7. Agents")
    agents = data.get("agents", {})
    configured = agents.get("configured", [])
    if configured:
        table(["Name", "Model", "Profile", "Enabled", "Subagent Access"], [
            [a["name"], redact(a.get("model", "default")), a.get("profile", "full"),
             "Yes" if a.get("enabled", True) else "No",
             "Yes" if a.get("subagent_access") else "No"]
            for a in configured
        ])
    agent_dirs = agents.get("directories", [])
    if agent_dirs:
        p(f"\n**Agent directories**: {', '.join(agent_dirs)}")
    p("")

    # --- 8. Subagent Limits ---
    h2("8. Subagent Limits")
    if config.get("agents", {}).get("defaults", {}).get("subagents"):
        sub = config["agents"]["defaults"]["subagents"]
        table(["Setting", "Value"], [[k, v] for k, v in sub.items()])
    else:
        p("Using defaults (not explicitly configured).")
    p("")

    # --- 9. Channel Bindings ---
    h2("9. Channel Bindings")
    bindings = data.get("bindings", [])
    if bindings:
        table(["Channel ID", "Agent", "Platform", "Require Mention"], [
            [b["id"], b["agent"], b.get("platform", "slack"), b.get("requireMention", True)]
            for b in bindings
        ])
    else:
        p("No channel bindings configured.")
    p("")

    # --- 10. Skills ---
    h2("10. Skills")
    skills = data.get("skills", [])
    if skills:
        table(["Skill", "Registered", "Enabled", "Scripts", "Description"], [
            [s["name"],
             "Yes" if s["registered"] else "dir-only",
             "Yes" if s["enabled"] else "No",
             ", ".join(s.get("scripts", [])) or "—",
             s.get("description", "")]
            for s in skills
        ])
    p("")

    # --- 11. Cron Jobs ---
    h2("11. Cron Jobs")
    cron = data.get("cron", [])
    if cron:
        table(["Source", "Name", "Schedule", "TZ", "Agent", "Enabled", "Status"], [
            [j["source"], j["name"][:50], j["schedule"], j.get("timezone", "UTC"),
             j.get("agent", "—"), "Yes" if j.get("enabled", True) else "No",
             j.get("status", "—")]
            for j in cron
        ])
    p("")

    # --- 12. Memory Architecture ---
    h2("12. Memory Architecture")
    memory = data.get("memory", {})
    qmd = memory.get("qmd", {})
    if qmd:
        p(f"- **Backend**: {qmd.get('backend', 'N/A')}")
        p(f"- **Provider**: {qmd.get('provider', 'N/A')}")
        search = qmd.get("search", {})
        if search:
            p(f"- **Search config**: {json.dumps(search, indent=2)}")
    proj_mems = memory.get("project_memories", [])
    if proj_mems:
        h3("Project Memory Files")
        for m in proj_mems:
            p(f"- {m}")
    mem_files = memory.get("memory_files", [])
    if mem_files:
        h3("Memory Store Files")
        for m in mem_files:
            p(f"- {m['name']} ({m['size']:,} bytes)")
    p("")

    # --- 13. Shared References ---
    h2("13. Shared References")
    refs_dir = OPENCLAW / "references"
    if refs_dir.exists():
        for f in sorted(refs_dir.iterdir()):
            p(f"- {f.name}")
    shared_dir = OPENCLAW / "shared"
    if shared_dir.exists():
        for f in sorted(shared_dir.iterdir()):
            if f.is_file():
                p(f"- shared/{f.name}")
    p("")

    # --- 14. External Integrations (MCP) ---
    h2("14. External Integrations")
    mcp = data.get("mcp", [])
    if mcp:
        for cfg in mcp:
            p(f"- **{cfg['path']}**: {', '.join(cfg.get('servers', []))}")
    else:
        p("No MCP configurations found.")
    p("")

    # --- 15. Plugins ---
    h2("15. Plugins")
    plugins = data.get("plugins", {})
    registered = plugins.get("registered", [])
    if registered:
        table(["Plugin", "Enabled"], [
            [pl["name"], "Yes" if pl["enabled"] else "No"] for pl in registered
        ])
    custom = plugins.get("custom", [])
    if custom:
        h3("Custom Plugins")
        for cp in custom:
            p(f"- **{cp['name']}**: {', '.join(cp['files'])}")
    p("")

    # --- 16. Hooks & Transforms ---
    h2("16. Hooks & Transforms")
    hooks = data.get("hooks", [])
    if hooks:
        for h in hooks:
            p(f"- **{h['name']}**: {', '.join(h['files'][:5])}")
    else:
        p("No hooks configured.")
    p("")

    # --- 17. Claude Code Configuration ---
    h2("17. Claude Code Configuration")
    cc = data.get("claude_settings", {})
    settings = cc.get("settings", {})
    if settings:
        p(f"```json\n{json.dumps(settings, indent=2)}\n```")
    local_perms = cc.get("local_permissions", {})
    if local_perms:
        p(f"\n**Local permissions**: {len(local_perms.get('permissions', {}).get('allow', []))} allow rules, "
          f"{len(local_perms.get('permissions', {}).get('deny', []))} deny rules")
    p("")

    # --- 18. Scripts & Utilities ---
    h2("18. Scripts & Utilities (`~/bin/`)")
    scripts = data.get("scripts", [])
    if scripts:
        table(["Script", "Type", "Size/Target"], [
            [s["name"], s["type"], s.get("target", f"{s.get('size', 0):,} bytes")]
            for s in scripts
        ])
    p("")

    # --- 19. Security & Permissions ---
    h2("19. Security & Permissions")
    sec = data.get("security", {})
    if sec.get("ssh_keys"):
        p(f"- **SSH keys**: {', '.join(sec['ssh_keys'])}")
    if sec.get("gateway_auth"):
        p(f"- **Gateway auth**: {sec['gateway_auth']}")
    if sec.get("rate_limit"):
        p(f"- **Rate limit**: {json.dumps(sec['rate_limit'])}")
    if sec.get("exec_approvals"):
        p(f"- **Exec approvals**: v{sec['exec_approvals'].get('version', '?')}, socket={'yes' if sec['exec_approvals'].get('has_socket') else 'no'}")
    if sec.get("slack_allowed_users"):
        p(f"- **Slack allowed users**: {sec['slack_allowed_users']}")
    p("")

    # --- 20. Key Counts Summary ---
    h2("20. Key Counts Summary")
    table(["Category", "Count"], [
        ["Agents (configured)", len(agents.get("configured", []))],
        ["Agents (directories)", len(agents.get("directories", []))],
        ["Skills", len(skills)],
        ["Channel Bindings", len(bindings)],
        ["Cron Jobs (total)", len(cron)],
        ["Cron Jobs (enabled)", sum(1 for j in cron if j.get("enabled", True))],
        ["Plugins", len(plugins.get("registered", []))],
        ["Custom Plugins", len(plugins.get("custom", []))],
        ["Hooks", len(hooks)],
        ["Memory Files", len(memory.get("memory_files", []))],
        ["Project Memories", len(memory.get("project_memories", []))],
        ["MCP Configs", len(mcp)],
        ["Tailscale Nodes", len(ts_data.get("nodes", []))],
        ["Scripts (~/bin)", len(scripts)],
    ])

    # --- 21. Known Issues ---
    h2("21. Known Issues")
    issues = []
    # Check for errored cron jobs
    for j in cron:
        if j.get("status") == "error":
            issues.append(f"Cron job **{j['name']}** is in error state")
        if not j.get("enabled", True) and j.get("status") == "error":
            issues.append(f"Cron job **{j['name']}** disabled with errors")
    # Check for offline tailscale nodes
    for n in ts_data.get("nodes", []):
        if "offline" in n.get("status", ""):
            issues.append(f"Tailscale node **{n['name']}** is {n['status']}")

    if issues:
        for issue in issues:
            p(f"- {issue}")
    else:
        p("No issues detected.")
    p("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="OpenClaw System Map Generator")
    parser.add_argument("--stdout", action="store_true", help="Write to stdout instead of file")
    parser.add_argument("--json", action="store_true", help="Output raw JSON instead of markdown")
    parser.add_argument("--output-dir", type=str, help="Custom output directory")
    args = parser.parse_args()

    # Collect all data
    hostname = collect_hostname()
    now = datetime.datetime.now(datetime.timezone.utc)
    timestamp = now.strftime("%Y-%m-%d %H:%M:%S UTC")
    file_ts = now.strftime("%Y%m%d-%H%M%S")

    config = collect_openclaw_config()

    data = {
        "timestamp": timestamp,
        "infrastructure": collect_infrastructure(),
        "network": collect_network(),
        "tailscale": collect_tailscale(),
        "docker": collect_docker(),
        "services": collect_services(),
        "config": config,
        "gateway": collect_gateway(config),
        "node": collect_node(),
        "agents": collect_agents(config),
        "bindings": collect_channel_bindings(config),
        "skills": collect_skills(config),
        "cron": collect_cron_jobs(),
        "memory": collect_memory(config),
        "plugins": collect_plugins(config),
        "hooks": collect_hooks(),
        "claude_settings": collect_claude_settings(),
        "scripts": collect_scripts(),
        "security": collect_security(config),
        "mcp": collect_mcp(),
    }

    if args.json:
        output = json.dumps(data, indent=2, default=str)
    else:
        output = render_markdown(data)

    if args.stdout:
        print(output)
        return

    # Determine output directory
    # Check tailscale-shared first (more specific), then shared (englebert1 convention)
    if args.output_dir:
        out_dir = pathlib.Path(args.output_dir)
    elif (HOME / "tailscale-shared").exists():
        out_dir = HOME / "tailscale-shared"
    elif (HOME / "shared").exists():
        out_dir = HOME / "shared"
    else:
        out_dir = HOME / "shared"
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"Created {out_dir}", file=sys.stderr)

    ext = "json" if args.json else "md"
    filename = f"openclaw-system-map_{hostname}_{file_ts}.{ext}"
    out_path = out_dir / filename

    with open(out_path, "w") as f:
        f.write(output)

    print(f"{out_path}")


if __name__ == "__main__":
    main()

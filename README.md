# OpenClaw Framework

Everything you need to stand up and operate a self-hosted AI agent server built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

This repo contains the scripts, skills, configuration examples, and documentation used to run a production [OpenClaw](https://openclaw.ai) deployment. Use it as a starting kit for your own build, or fork it and make it yours.

## Quick start

### Prerequisites (do these first)

1. A **Tailscale** account (free) — [tailscale.com](https://tailscale.com)
2. A **Claude** account ($20/mo Max plan) — [claude.ai](https://claude.ai) + an API key from [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
3. A **Linux server** — Hostinger VPS recommended ($14.99/mo), Ubuntu 24.04. [Other options](guide/linux-setup-options.md)

### Three commands to get started

SSH into your server, then:

```bash
# 1. Bootstrap (installs Node.js + Claude Code)
curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash

# 2. Authenticate
claude login

# 3. Let Claude Code set up everything else
claude --dangerously-skip-permissions
```

When Claude Code starts, paste this prompt:

> Follow the setup instructions in the "Server setup (for Claude Code)" section of https://github.com/mikeengleai/openclaw-framework to configure this server.

Claude Code handles all remaining installation and configuration. You just approve the commands as it goes.

After setup is complete, exit Claude Code and run `cw` to create your first workspace.

---

## Server setup (for Claude Code)

**These instructions are for Claude Code to follow.** When a user tells you to set up this server, execute these steps in order.

### Step 1: System dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip python3-venv sqlite3 tmux curl jq unzip
pip3 install cryptography 2>/dev/null || pip3 install --break-system-packages cryptography
```

### Step 2: Install OpenClaw

```bash
sudo npm install -g openclaw
openclaw init
```

### Step 3: Install agent-browser

```bash
sudo npm install -g agent-browser
mkdir -p ~/.agent-browser/profiles
```

### Step 4: Install Tailscale (if not already installed)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

The user will need to authenticate via the browser link that Tailscale prints.

### Step 5: Clone and install this framework

```bash
git clone https://github.com/mikeengleai/openclaw-framework.git ~/openclaw-framework
~/openclaw-framework/install.sh
source ~/.bashrc
```

This installs:
- `cw` — Claude Workspaces manager → `~/bin/cw`
- `import-cookies` — browser cookie import tool → `~/bin/import-cookies`
- `compaction-prompt.md` — memory compaction curator → `~/bin/`

### Step 6: Create workspaces directory

```bash
mkdir -p ~/workspaces
```

### Step 7: Verify everything works

Run each of these and confirm they succeed:

```bash
node -v                    # Node.js 20+
python3 --version          # Python 3.10+
sqlite3 --version          # SQLite
tmux -V                    # tmux
openclaw --version         # OpenClaw
agent-browser --version    # agent-browser
cw --help                  # Claude Workspaces
tailscale status           # Tailscale connected
```

Report the results to the user. If anything failed, fix it before proceeding.

---

## After setup: using the system

### Create your first workspace

Exit Claude Code, then:

```bash
cw
```

Select **[n] Create new workspace**, give it a name and description. Launch it. You're now in an isolated Claude Code session with its own memory.

### Connect a messaging channel (WhatsApp, Slack, Telegram)

From inside Claude Code or from the command line:

```bash
# Install the channel plugin (pick one)
openclaw plugins install @openclaw/whatsapp
openclaw plugins install @openclaw/slack
openclaw plugins install clawhub:@openclaw/telegram

# Add the channel
openclaw channels add --channel whatsapp    # guided setup
openclaw channels login --channel whatsapp  # scan QR code with your phone
```

For WhatsApp: a QR code appears in the terminal. Scan it with WhatsApp on your phone. This is the one step that requires manual interaction.

### Create your first agent

Inside a `cw` workspace, tell Claude Code what you want:

> Create a web research agent that can browse the web and search YouTube. It should be able to answer questions by searching the internet and summarizing what it finds.

Claude Code will configure the agent, set up the browsing profile, and wire it to your messaging channel.

### Import browser cookies (for authenticated browsing)

Export cookies from your laptop browser using the [Cookie-Editor](https://cookie-editor.com) extension, then either:

- **Via messaging:** Paste the JSON into your WhatsApp/Slack channel with "import these cookies into the youtube profile"
- **Via command line:** `import-cookies --profile youtube --from ~/cookies.json`

See the full [authenticated browsing guide](guide/authenticated-browsing.md) for details on exit nodes and profile management.

---

## What's in the repo

| Directory | What it is |
|---|---|
| `bin/` | **Claude Workspaces** (`cw`), **import-cookies**, and memory compaction prompt |
| `skills/system-map/` | **Daily system map** — Python collector that snapshots your entire system to markdown |
| `skills/system-upgrade/` | **System upgrade** — 10 checkpointed bash scripts for safe OS and OpenClaw upgrades |
| `guide/` | **Build guides** — companion guide, linux setup options, authenticated browsing |
| `server-maps/` | **Example server map** — a real production system map snapshot |
| `examples/` | **Templates** — sample cron jobs and agent model configurations |

## Guides

- [Companion build guide](guide/companion-guide.md) — 14-section step-by-step from Tailscale to troubleshooting
- [Linux setup options](guide/linux-setup-options.md) — Hostinger VPS, WSL, or Mac dual-boot
- [Authenticated browsing](guide/authenticated-browsing.md) — exit nodes, agent-browser profiles, cookie import

## Resources

- **OpenClaw:** [openclaw.ai](https://openclaw.ai)
- **Claude Code:** [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code)
- **Tailscale:** [tailscale.com](https://tailscale.com)

## License

Apache 2.0. See [LICENSE](LICENSE).

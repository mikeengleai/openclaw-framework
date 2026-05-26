# OpenClaw Framework

Everything you need to stand up and operate a self-hosted AI agent server built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

This repo contains the scripts, skills, configuration examples, and documentation used to run a production [OpenClaw](https://openclaw.ai) deployment. Use it as a starting kit for your own build, or fork it and make it yours.

## Quick start

### Prerequisites (do these first)

1. A **Tailscale** account (free) — [tailscale.com](https://tailscale.com)
2. A **Claude** account ($20/mo Max plan) — [claude.ai](https://claude.ai) + an API key from [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
3. A **Linux server** — Hostinger VPS recommended ($14.99/mo), Ubuntu 24.04. [Other options](guide/linux-setup-options.md)

### Step 1: Bootstrap (as root)

SSH into your server and run:

```bash
curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash
```

This installs Node.js, git, Claude Code, and creates the `openclaw` user.

### Step 2: Launch Claude Code and authenticate

```bash
su - openclaw
claude --dangerously-skip-permissions
```

Once Claude Code starts, type:

```
/login
```

Follow the browser link to authenticate with your Anthropic account. After login completes, paste this prompt:

> Follow the setup instructions in the "Server setup (for Claude Code)" section of https://github.com/mikeengleai/openclaw-framework to configure this server.

Claude Code handles all remaining installation and configuration. You just approve the commands as it goes. When it finishes and reports verification results, exit Claude Code.

### Step 4: Connect WhatsApp (manual step — must be done outside Claude Code)

This step requires you to scan a QR code, so it must be run directly in the terminal, not inside Claude Code.

```bash
# Install the WhatsApp plugin
openclaw plugins install @openclaw/whatsapp

# Add the channel
openclaw channels add --channel whatsapp

# Link your phone — a QR code will appear in the terminal
# Scan it with WhatsApp on your phone: Settings → Linked Devices → Link a Device
openclaw channels login --channel whatsapp
```

**Tip:** If the QR code is too large for your terminal, use Ctrl+scroll wheel to shrink the font, or maximize the window first.

After scanning, configure the gateway:

```bash
# Set gateway mode
openclaw config set gateway.mode local

# Find your WhatsApp user ID
openclaw channels resolve whatsapp <your-phone-number>

# Set yourself as the command owner (replace the ID below with your actual ID)
openclaw config set commands.ownerAllowFrom '["whatsapp:<your-whatsapp-id>"]'

# Run the doctor to clean up and validate
openclaw doctor

# Start the gateway (foreground, since systemd user services may not be available)
nohup openclaw gateway --foreground &>/dev/null &
```

**Alternative channels:** Replace `whatsapp` with `slack` or `telegram` in the commands above. For Slack, use `openclaw plugins install @openclaw/slack`. For Telegram, use `openclaw plugins install clawhub:@openclaw/telegram`.

### Step 5: Start building

```bash
source ~/.bashrc
cw
```

Select **[n] Create new workspace**, give it a name, and launch it. You're now in an isolated Claude Code session with its own memory. Tell it what you want to build.

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

If `openclaw init` is not a valid command in this version, skip it — OpenClaw will create its config directory on first use.

### Step 3: Install agent-browser and Chrome

```bash
sudo npm install -g agent-browser
agent-browser install --with-deps
mkdir -p ~/.agent-browser/profiles
```

`agent-browser install --with-deps` downloads a compatible Chrome binary and installs the system libraries it needs (libx11, libatk, libcups, etc.). This is required before any browsing will work.

### Step 4: Install Tailscale (if not already installed)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

The user will need to authenticate via the browser link that Tailscale prints. If Tailscale is already installed, skip this step.

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

### Step 7: Install the Superpowers plugin for Claude Code

```bash
claude plugins add https://github.com/obra/superpowers
```

This adds brainstorming, TDD, debugging, and planning skills to all future Claude Code sessions.

### Step 8: Configure gateway mode

```bash
openclaw config set gateway.mode local
```

### Step 9: Run doctor

```bash
openclaw doctor
```

This cleans up unavailable skills/plugins and validates the configuration.

### Step 10: Verify everything works

Run each of these and confirm they succeed:

```bash
node -v                    # Node.js 20+
python3 --version          # Python 3.10+
sqlite3 --version          # SQLite
tmux -V                    # tmux
openclaw --version         # OpenClaw
agent-browser --version    # agent-browser
cw --help                  # Claude Workspaces
```

Report the results to the user. If anything failed, fix it before proceeding.

Tell the user: "Server setup is complete. Exit Claude Code, then follow Step 4 in the Quick Start section of the README to connect WhatsApp (this must be done outside Claude Code because you need to scan a QR code). After that, run `cw` to create your first workspace."

---

## After setup: using the system

### Import browser cookies (for authenticated browsing)

Export cookies from your laptop browser using the [Cookie-Editor](https://cookie-editor.com) extension, then inside a `cw` workspace paste the JSON into Claude Code:

> Import these YouTube cookies into an agent-browser profile called "youtube":
> ```
> [paste JSON here]
> ```

Or send the cookie JSON via WhatsApp to your agent once the channel is connected.

See the full [authenticated browsing guide](guide/authenticated-browsing.md) for details on exit nodes and profile management.

### Create your first agent

Inside a `cw` workspace, tell Claude Code what you want:

> Create a web research agent that can browse the web and search YouTube. It should be able to answer questions by searching the internet and summarizing what it finds.

Claude Code will configure the agent, set up the browsing profile, and wire it to your messaging channel.

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

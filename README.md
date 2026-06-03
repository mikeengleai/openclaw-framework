# OpenClaw Framework

Everything you need to stand up and operate a self-hosted AI agent server built on OpenClaw and managed with Claude Code

This repo contains the scripts, skills, configuration examples, and documentation for running a production [OpenClaw](https://openclaw.ai) deployment. Use it as a starting kit for your own build, or fork it and make it yours.

## Quick start

---

> **What you need before starting.** Three accounts and a Linux server. Total monthly cost is about $35, and "pre-setup" takes 5-10 minutes.

### Prerequisites (do these first)

1. A **Tailscale** account (free) - [tailscale.com](https://tailscale.com)
2. A **Claude** account ($20/mo Max plan) - [claude.ai](https://claude.ai) + an API key from [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) - the API key can be done later.
3. A **Linux server** - Hostinger VPS recommended ($14.99/mo with no annual commitment), Ubuntu 24.04. [Other options](guide/linux-setup-options.md)

---

> **Installing the foundation.** This step puts Node.js, git, and Claude Code on a blank server and creates a dedicated `openclaw` user so nothing runs as root. Takes about 2 minutes.

### Phase 1: Bootstrap (as root)

SSH into your server and run:

curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash

This installs Node.js, git, Claude Code, and creates the `openclaw` user.

---

> **Linking your Claude subscription.** Claude Code needs to authenticate before OpenClaw installs, because OpenClaw borrows Claude's OAuth credentials during onboarding.

### Phase 2: Authenticate Claude Code (as openclaw)
su - openclaw

claude --dangerously-skip-permissions

Once Claude Code starts, type `/login` and follow the link in your browser to authenticate with your Anthropic account. Then type `exit` to leave Claude Code.

---

> **Creating your private network.** Tailscale builds an encrypted mesh between your devices. Once your server is on Tailscale, you can reach its dashboards and services from your laptop or phone without exposing anything to the public internet.

### Phase 3: Connect to Tailscale
curl -fsSL https://tailscale.com/install.sh | bash

sudo tailscale up

Follow the link it prints to authorize your server. This connects it to your Tailscale network so you can reach dashboards and services from your other devices later.

---

> **Installing the agent framework.** OpenClaw is what manages your agents, channels, memory, and scheduled jobs. The onboard wizard handles configuration interactively so you don't need to memorize commands.

### Phase 4: Install and onboard OpenClaw

OpenClaw uses Claude's OAuth credentials, so Claude Code must be authenticated first.
curl -fsSL https://openclaw.ai/install.sh | bash

Then:
source ~/.bashrc && openclaw setup && openclaw onboard

The `onboard` wizard walks you through everything interactively: API key, WhatsApp pairing (scan the QR code), gateway configuration, and owner setup. Follow the prompts.

**Tip:** If the WhatsApp QR code is too large for your terminal, use Ctrl+scroll wheel to shrink the font, or maximize the window first.

**Alternative channels:** When onboard asks about channels, you can choose `slack` or `telegram` instead of WhatsApp.

---

> **Adding the tools that make it usable.** QMD for databases, agent-browser for web access, tmux for persistent sessions, and the Claude Workspaces (`cw`) manager that ties it all together.

### Phase 5: Install tools and dependencies
curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/post-onboard.sh | bash
source ~/.bashrc

This installs system dependencies (python3, sqlite3, tmux, jq), agent-browser with Chrome, the framework tools (`cw`, `import-cookies`), and the Superpowers plugin for Claude Code. It verifies everything at the end.

---

> **Going live.** Start the gateway, open your first workspace, and start building. From here on, you manage everything through Claude Code.

### Phase 6: Start the gateway and build
# Start the OpenClaw gateway
nohup openclaw gateway --foreground &>/dev/null &

# Launch your first workspace - This is a simple script that lets you keep your projects running even if your windows close, and keeps everything together in groups so you can pick things up
cw

Select **[n] Create new workspace**, give it a name, and launch it. You're now in an isolated Claude Code session with its own memory. Tell it what you want to build.

---
But first, type this command - **This is gold**
/remote-control

This puts a copy of this session into your Claude Code web/mobile view so you can work on it from anywhere.  No more terminal needed until you want to launch a different one.
---

> **Your server is running. Now what?** Here are starter projects that show what you can do with a live OpenClaw server. Each one can be built in a single Claude Code session.

## After setup: things you can build

Your server is running, your agent is reachable via WhatsApp/Slack/Telegram, and Claude Code is ready. Here are some things you can do with this setup now.

### 1. Connect Google Email and Calendar

Give your agent access to Gmail and Google Calendar so it can read, draft, and manage email and calendar events on your behalf.

#### Set up Google Cloud credentials

1. Go to [console.cloud.google.com](https://console.cloud.google.com/) and create a new project (e.g., "OpenClaw Agent")
2. Enable the **Gmail API** and **Google Calendar API**:
   - Navigate to **APIs & Services > Library**
   - Search for "Gmail API", click it, click **Enable**
   - Search for "Google Calendar API", click it, click **Enable**
3. Create OAuth 2.0 credentials:
   - Go to **APIs & Services > Credentials**
   - Click **Create Credentials > OAuth client ID**
   - Application type: **Desktop app**
   - Name it (e.g., "OpenClaw Agent")
   - Download the JSON file
4. Configure the OAuth consent screen:
   - Go to **APIs & Services > OAuth consent screen**
   - User type: **External** (or Internal if using Google Workspace)
   - Fill in the app name and your email
   - Add scopes: `gmail.modify`, `gmail.send`, `calendar.events`, `calendar.readonly`
   - Add your email as a test user

#### Connect it to your agent

Open a `cw` workspace and tell Claude Code:

> Set up Google email and calendar access. Here are my OAuth credentials:
> ```
> [paste the downloaded JSON here]
> ```
> Configure Gmail so I can read, search, draft, and send email. Configure Google Calendar so I can view and create events. Use the `ms365` or `gmail` skill pattern.

Claude Code will store the credentials, run the OAuth flow (you'll authorize in your browser), and wire the skills to your agent.

### 2. Web Researcher

Search the web and YouTube daily for topics that interest you, store results in a database, and publish a dashboard you can check from any device on your Tailscale network.

#### Set up a Tailscale exit node (recommended)

An exit node routes your agent's web traffic through a machine you control (typically your home computer), so websites see your residential IP instead of a datacenter IP. This helps avoid bot detection and CAPTCHAs.

On your **home machine** (Windows, Mac, or Linux):

1. Install Tailscale if you haven't already: [tailscale.com/download](https://tailscale.com/download)
2. Enable exit node advertising:
   - **Windows/Mac**: Open Tailscale settings, check "Run as exit node"
   - **Linux**: `sudo tailscale up --advertise-exit-node`
3. Approve the exit node in the Tailscale admin console: [login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines) - click the machine, enable "Use as exit node"

On your **server**, tell it to route traffic through your home machine:

```bash
sudo tailscale up --exit-node=<your-home-machine-tailscale-ip>
```

Now all outbound traffic from your server (including agent-browser) goes through your home network.

#### Import YouTube cookies

YouTube requires authentication for some content. Export cookies from your laptop browser:

1. Install the [Cookie-Editor](https://cookie-editor.com) browser extension
2. Go to [youtube.com](https://youtube.com) (make sure you're logged in)
3. Click the Cookie-Editor icon and click **Export** (JSON format)
4. In your `cw` workspace, paste the cookies when Claude Code asks for them

See the full [authenticated browsing guide](guide/authenticated-browsing.md) for details on exit nodes and profile management.

#### Tell Claude Code what to research

Open a `cw` workspace and paste a prompt like this (customize the topic and channels):

> Follow the first research project guide at https://github.com/mikeengleai/openclaw-framework/blob/main/guide/first-research-project.md
>
> My research topic: AI Security News
>
> YouTube channels to monitor:
> - https://www.youtube.com/@AgenticAI-Foundation
> - https://www.youtube.com/@IBMTechnology
> - https://www.youtube.com/@AISecurityPodcast

Or skip the guide and describe what you want directly:

> Create a web research agent that can browse the web and search YouTube. It should be able to answer questions by searching the internet and summarizing the results.
>
> It should search YouTube and Brave web search for the latest daily updates about Hermes, OpenClaw, and other "harness" tools and keep track of the latest trends. Then, publish it to a local tailnet server, running persistently on reboot, so I can view the results daily. If I have any control channels set up like whatsapp or telegram, send me a notice when the new results are ready. Run the search daily at 6am EST.

Claude Code will set up QMD (the research database), import your YouTube cookies, configure Brave web searches, build a collector script, deploy a dashboard on your Tailnet, and schedule daily updates with notifications to your messaging channel.

---

## What's in the repo

| Directory | What it is |
|---|---|
| `bin/` | **Claude Workspaces** (`cw`), **import-cookies**, and memory compaction prompt |
| `skills/system-map/` | **Daily system map** - Python collector that snapshots your entire system to markdown |
| `skills/system-upgrade/` | **System upgrade** - 10 checkpointed bash scripts for safe OS and OpenClaw upgrades |
| `guide/` | **Build guides** - companion guide, linux setup options, authenticated browsing |
| `server-maps/` | **Example server map** - a real production system map snapshot |
| `examples/` | **Templates** - sample cron jobs and agent model configurations |

## Guides

- [Companion build guide](guide/companion-guide.md) - 14-section step-by-step from Tailscale to troubleshooting
- [Linux setup options](guide/linux-setup-options.md) - Hostinger VPS, WSL, or Mac dual-boot
- [Authenticated browsing](guide/authenticated-browsing.md) - exit nodes, agent-browser profiles, cookie import
- [First research project](guide/first-research-project.md) - daily web + YouTube monitoring with QMD and a Tailnet dashboard
- [Operations guide](guide/operations-guide.md) - using `cw`, `/remote-control`, Superpowers, building agents, research pipelines, and QMD

## Resources

- **OpenClaw:** [openclaw.ai](https://openclaw.ai)
- **Claude Code:** [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code)
- **Tailscale:** [tailscale.com](https://tailscale.com)

## License

Apache 2.0. See [LICENSE](LICENSE).

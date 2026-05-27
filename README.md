# OpenClaw Framework

Everything you need to stand up and operate a self-hosted AI agent server built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

This repo contains the scripts, skills, configuration examples, and documentation used to run a production [OpenClaw](https://openclaw.ai) deployment. Use it as a starting kit for your own build, or fork it and make it yours.

## Quick start

### Prerequisites (do these first)

1. A **Tailscale** account (free) — [tailscale.com](https://tailscale.com)
2. A **Claude** account ($20/mo Max plan) — [claude.ai](https://claude.ai) + an API key from [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
3. A **Linux server** — Hostinger VPS recommended ($14.99/mo), Ubuntu 24.04. [Other options](guide/linux-setup-options.md)

### Phase 1: Bootstrap (as root)

SSH into your server and run:

```bash
curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash
```

This installs Node.js, git, Claude Code, and creates the `openclaw` user.

### Phase 2: Authenticate Claude Code (as openclaw)

```bash
su - openclaw
claude --dangerously-skip-permissions
```

Once Claude Code starts, type `/login` and follow the browser link to authenticate with your Anthropic account. Then type `exit` to leave Claude Code.

### Phase 3: Install and onboard OpenClaw

OpenClaw uses Claude's OAuth credentials, so Claude Code must be authenticated first.

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

Then:

```bash
source ~/.bashrc && openclaw setup && openclaw onboard
```

The `onboard` wizard walks you through everything interactively: API key, WhatsApp pairing (scan the QR code), gateway configuration, and owner setup. Follow the prompts.

**Tip:** If the WhatsApp QR code is too large for your terminal, use Ctrl+scroll wheel to shrink the font, or maximize the window first.

**Alternative channels:** When onboard asks about channels, you can choose `slack` or `telegram` instead of WhatsApp.

### Phase 4: Install tools and dependencies

```bash
curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/post-onboard.sh | bash
source ~/.bashrc
```

This installs system dependencies (python3, sqlite3, tmux, jq), agent-browser with Chrome, Tailscale, the framework tools (`cw`, `import-cookies`), and the Superpowers plugin for Claude Code. It verifies everything at the end.

If Tailscale needs authentication, run `sudo tailscale up` after the script finishes.

### Phase 5: Start the gateway and build

```bash
# Start the OpenClaw gateway
nohup openclaw gateway --foreground &>/dev/null &

# Launch your first workspace
cw
```

Select **[n] Create new workspace**, give it a name, and launch it. You're now in an isolated Claude Code session with its own memory. Tell it what you want to build.

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
- [First research project](guide/first-research-project.md) — daily web + YouTube monitoring with QMD and a Tailnet dashboard

## Resources

- **OpenClaw:** [openclaw.ai](https://openclaw.ai)
- **Claude Code:** [docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code)
- **Tailscale:** [tailscale.com](https://tailscale.com)

## License

Apache 2.0. See [LICENSE](LICENSE).

# OpenClaw: companion implementation guide

**Prepared for:** OpenClaw talk attendees
**Send ahead:** 1 hour before the session
**GitHub repo:** [github.com/openclaw-framework](https://github.com/openclaw-framework) (scripts and sample configs referenced below)

---

## How to use this guide

Each section maps to a chapter in the live talk. Read the sections that match your interest level before the session. During the talk, Mike will reference specific sections so you can follow along.

Prerequisites for the full build:
- A Linux VPS ($5-30/month, Hostinger or equivalent)
- A credit card for Anthropic API access
- A Slack workspace you control (or Telegram/WhatsApp as an alternative)
- 2-3 hours for initial setup

If you already run your own Linux servers, skip to section 5.

---

## Section 1: create a Tailscale account and add your devices

**Maps to:** Chapter 1 (Linux and Tailscale foundation)

Tailscale creates a private mesh network across all your devices using WireGuard under the hood. Every device gets a stable IP address that works regardless of NAT, firewalls, or physical location. Your VPS, laptop, phone, and tablet all join the same network.

### Steps

1. Go to tailscale.com and create an account. Google or GitHub SSO works.
2. Install the Tailscale client on your laptop or desktop.
   - macOS: `brew install tailscale` or download from the Mac App Store
   - Windows: download the installer from tailscale.com/download
   - Linux: `curl -fsSL https://tailscale.com/install.sh | sh`
3. Run `tailscale up` and authenticate through the browser.
4. Note the IP address assigned to your device: `tailscale ip -4`
5. Install Tailscale on your phone (iOS App Store or Google Play).
6. Authenticate on your phone with the same account.
7. Verify both devices see each other: `tailscale status`

### Expected output

`tailscale status` shows both devices with their Tailscale IPs, both marked as active.

### Common failures

- **"tailscale up" hangs:** Your network may block UDP on port 41641. Tailscale falls back to DERP relay servers, which is slower but functional. Check with your IT department if on a corporate network.
- **Device shows "offline" immediately after setup:** Restart the Tailscale service. On Linux: `sudo systemctl restart tailscaled`
- **Two accounts by mistake:** If you authenticated your phone with a different email, remove the device from the admin console and re-authenticate.

### Why Tailscale and not a traditional VPN

Traditional VPNs route all traffic through a central server. Tailscale creates direct peer-to-peer connections between your devices. No single point of failure, no bandwidth bottleneck, no VPN server to maintain. The mesh topology means your phone connects directly to your VPS without touching your laptop.

---

## Section 2: sign up for a Hostinger Linux VPS

**Maps to:** Chapter 1 (Linux and Tailscale foundation)

The OpenClaw production server runs on a Hostinger VPS with an AMD EPYC 9354P processor, 8 vCPU, 32 GB RAM, and 387 GB disk. That configuration costs roughly $30/month. You can start smaller.

### Steps

1. Go to hostinger.com and create an account.
2. Choose a VPS plan. Minimum recommended: 4 vCPU, 8 GB RAM, 100 GB disk. The $10-15/month tier works for a single-agent setup.
3. Select Ubuntu 24.04 LTS as the operating system.
4. Choose a data center region close to you geographically.
5. Set a root password during provisioning. You will replace password auth with SSH keys in the next section.
6. Note the public IP address assigned to your VPS.
7. Verify you can reach it: `ssh root@<public-ip>`

### Expected output

A root shell on your new VPS.

### Common failures

- **SSH connection refused:** Hostinger may take 2-3 minutes after provisioning before SSH is ready. Wait and retry.
- **"Permission denied":** Double-check the password. Hostinger sends it via email if you miss the provisioning screen.

### Alternatives to Hostinger

Any Linux VPS provider works. DigitalOcean, Linode, Vultr, and Hetzner all offer comparable plans. The guide uses Hostinger because that is what the production system runs on.

---

## Section 3: lock down the Linux server

**Maps to:** Chapter 1 (Linux and Tailscale foundation)

Before installing anything, close the attack surface. The goal: SSH access only through Tailscale, no public-facing ports except what you explicitly open later.

### Steps

1. Create a non-root user:
   ```bash
   adduser openclaw
   usermod -aG sudo openclaw
   ```

2. Set up SSH key authentication from your laptop:
   ```bash
   # On your laptop
   ssh-keygen -t ed25519 -C "openclaw-vps"
   ssh-copy-id openclaw@<public-ip>
   ```

3. Disable password authentication:
   ```bash
   sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
   sudo systemctl restart sshd
   ```

4. Install Tailscale on the VPS:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

5. Authenticate through the browser link Tailscale prints.

6. Note the Tailscale IP: `tailscale ip -4`

7. Configure the firewall to allow SSH only from Tailscale:
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow in on tailscale0
   sudo ufw enable
   ```

8. Verify you can SSH via the Tailscale IP:
   ```bash
   ssh openclaw@<tailscale-ip>
   ```

9. Once confirmed, remove the public IP SSH rule if your provider's firewall allows it.

10. Verify the lockdown: try to SSH via the public IP from a device not on your tailnet. It should be refused.

### Expected output

SSH works via Tailscale IP. SSH via public IP is blocked. `sudo ufw status` shows only tailscale0 rules.

### Common failures

- **Locked yourself out:** Most VPS providers offer a web console (VNC/KVM) through their dashboard. Use it to fix firewall rules if you lose SSH access.
- **Tailscale not starting on boot:** Run `sudo systemctl enable tailscaled`
- **UFW blocks Tailscale:** Make sure the `allow in on tailscale0` rule is added before you `ufw enable`.

---

## Section 4: install Node.js, npm, Python, SQLite, tmux

**Maps to:** Chapter 2 (the development loop)

OpenClaw runs on Node.js. Several skills use Python scripts. SQLite backs the QMD memory system. tmux lets you run multiple persistent terminal sessions.

### Steps

1. Update the system:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. Install Node.js 20 LTS:
   ```bash
   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
   sudo apt install -y nodejs
   ```

3. Verify Node and npm:
   ```bash
   node --version   # should show v20.x
   npm --version
   ```

4. Install Python 3 and pip:
   ```bash
   sudo apt install -y python3 python3-pip python3-venv
   ```

5. Install SQLite:
   ```bash
   sudo apt install -y sqlite3
   ```

6. Install tmux:
   ```bash
   sudo apt install -y tmux
   ```

7. Install additional utilities:
   ```bash
   sudo apt install -y git curl jq unzip
   ```

8. Verify all tools:
   ```bash
   node -v && npm -v && python3 --version && sqlite3 --version && tmux -V && git --version
   ```

### Expected output

Version numbers for all six tools printed without errors.

### Common failures

- **Node.js version too old:** The default Ubuntu 24 repos ship Node 18. Use the NodeSource setup script above to get Node 20.
- **pip install fails with "externally managed":** Use `python3 -m venv` to create a virtual environment, or pass `--break-system-packages` if you understand the implications.

---

## Section 5: install OpenClaw

**Maps to:** Chapter 3 (OpenClaw anatomy and vocabulary)

OpenClaw installs via npm. The production server (srv1456044) runs a native npm install. The canary server (englebert1) runs inside Docker. This guide covers the native install.

### Steps

1. Install OpenClaw globally:
   ```bash
   sudo npm install -g openclaw
   ```

2. Run the initial setup:
   ```bash
   openclaw init
   ```

3. This creates the `~/.openclaw/` directory with the default structure:
   ```
   ~/.openclaw/
   ├── config.json          # global settings
   ├── agents/              # agent configurations
   │   └── default/         # the default agent
   ├── skills/              # skill packages
   ├── memory/              # QMD databases
   └── scripts/             # utility scripts
   ```

4. Set your Anthropic API key:
   ```bash
   openclaw config set apiKey <your-anthropic-api-key>
   ```

5. Set the default model:
   ```bash
   openclaw config set model anthropic/claude-sonnet-4-6
   ```

6. Start the gateway:
   ```bash
   openclaw gateway start
   ```

7. Verify it is running:
   ```bash
   curl http://localhost:18789/health
   ```

8. Create a systemd service for persistence:
   ```bash
   sudo tee /etc/systemd/system/openclaw-gateway.service > /dev/null <<'EOF'
   [Unit]
   Description=OpenClaw Gateway
   After=network.target

   [Service]
   Type=simple
   User=openclaw
   ExecStart=/usr/bin/openclaw gateway start
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   EOF

   sudo systemctl daemon-reload
   sudo systemctl enable openclaw-gateway
   sudo systemctl start openclaw-gateway
   ```

9. Verify the service:
   ```bash
   sudo systemctl status openclaw-gateway
   ```

### Expected output

Gateway running on port 18789, health endpoint returns OK, systemd service active.

### Common failures

- **"openclaw: command not found":** The npm global bin directory may not be in your PATH. Run `npm config get prefix` and add `<prefix>/bin` to your PATH in `~/.bashrc`.
- **Port 18789 already in use:** Another service is on that port. Change it in `~/.openclaw/config.json` or stop the conflicting service.
- **API key invalid:** Verify your key at console.anthropic.com. Make sure you have credits loaded.

---

## Section 6: configure your first agent

**Maps to:** Chapter 3 (OpenClaw anatomy and vocabulary)

An agent is a named configuration that binds a model, a profile, optional skills, and optional channel bindings. The production server runs 25 agents. You start with one.

### Steps

1. Create an agent directory:
   ```bash
   mkdir -p ~/.openclaw/agents/my-assistant
   ```

2. Create the agent configuration:
   ```bash
   cat > ~/.openclaw/agents/my-assistant/agent.json <<'EOF'
   {
     "name": "my-assistant",
     "model": "anthropic/claude-sonnet-4-6",
     "profile": "full",
     "enabled": true,
     "skills": [],
     "subagentAccess": false
   }
   EOF
   ```

3. Register the agent:
   ```bash
   openclaw agent register my-assistant
   ```

4. Test it:
   ```bash
   openclaw agent chat my-assistant "What is your name and what can you do?"
   ```

5. Review the agent profiles available:
   - **full**: all capabilities, highest token usage
   - **coding**: optimized for code tasks, moderate token usage
   - **minimal**: lightweight, lowest token usage

6. Once your first agent works, look at the sample agent configs in the GitHub repo (`agents/` directory) for patterns you can adapt.

### Expected output

The agent responds with its name and a description of its capabilities.

### Common failures

- **"Agent not found":** Make sure the directory name matches the name in agent.json, and that you ran `openclaw agent register`.
- **Model errors:** Verify your API key has access to the specified model. Sonnet 4.6 requires an Anthropic API key with sufficient credits.

### Anatomy of an agent config

| Field | Purpose | Production example |
|---|---|---|
| name | Identifier, used in channel bindings and logs | `outlook-engle` |
| model | Which LLM to use | `anthropic/claude-opus-4-7` |
| profile | Capability level | `coding` |
| enabled | Whether the agent is active | `true` |
| skills | Array of registered skill names | `["ms365", "hubspot", "gsheets"]` |
| subagentAccess | Can this agent spawn subagents | `false` |

---

## Section 7: set up QMD memory backend

**Maps to:** Chapter 4 (QMD)

QMD is a SQLite-backed per-agent memory system with structured frontmatter. Tobi Lutke (Shopify founder) created it. Each agent gets its own `.sqlite` file. QMD replaces the flat-markdown-on-disk pattern most early agent stacks use.

### Steps

1. Verify SQLite is installed:
   ```bash
   sqlite3 --version
   ```

2. Configure OpenClaw to use QMD:
   ```bash
   openclaw config set memoryBackend qmd
   ```

3. The memory directory is `~/.openclaw/memory/`. QMD creates SQLite files here automatically as agents accumulate context.

4. After your agent has processed a few conversations, check that memory files exist:
   ```bash
   ls -lh ~/.openclaw/memory/*.sqlite
   ```

5. Query a memory file directly (useful for debugging):
   ```bash
   sqlite3 ~/.openclaw/memory/my-assistant.sqlite ".tables"
   ```

6. To search memory content across all agents:
   ```bash
   for f in ~/.openclaw/memory/*.sqlite; do
     echo "=== $(basename $f) ==="
     sqlite3 "$f" "SELECT substr(content, 1, 100) FROM memories WHERE content LIKE '%search-term%';"
   done
   ```

### Expected output

After a few agent interactions, `.sqlite` files appear in `~/.openclaw/memory/` and grow as the agent accumulates context.

### Why QMD over flat files

Flat markdown files work until you have dozens of agents writing thousands of memory entries. At that point, searching across agents becomes slow and fragile. QMD uses SQLite, which handles concurrent reads, supports full-text search, and produces a single portable file per agent. The production server has memory files ranging from 16 KB (mktg-product-intelligence) to 30 MB (youtube_kb).

### Common failures

- **Memory files not appearing:** The agent needs to process at least one conversation that triggers a memory write. Try asking the agent to remember a specific fact, then check again.
- **SQLite "database is locked":** Two processes writing to the same file simultaneously. QMD handles this with WAL mode, but if you are running manual queries while an agent is active, close your manual connection first.

---

## Section 8: set up the browsing service

**Maps to:** Chapter 6 (browsing, scraping, content ingestion)

The agent-browser skill gives agents a persistent browser context with cookie storage on disk and screenshot artifacts. This is how agents interact with websites that require authentication, like LinkedIn and YouTube.

### Steps

1. Install browser dependencies:
   ```bash
   sudo apt install -y chromium-browser xvfb
   ```

2. Set up a virtual display (required for headless browsing with cookie persistence):
   ```bash
   sudo tee /etc/systemd/system/xvfb.service > /dev/null <<'EOF'
   [Unit]
   Description=X Virtual Frame Buffer
   After=network.target

   [Service]
   Type=simple
   ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24
   Restart=always

   [Install]
   WantedBy=multi-user.target
   EOF

   sudo systemctl daemon-reload
   sudo systemctl enable xvfb
   sudo systemctl start xvfb
   ```

3. Set the DISPLAY variable in your shell profile:
   ```bash
   echo 'export DISPLAY=:99' >> ~/.bashrc
   source ~/.bashrc
   ```

4. Verify the browser launches:
   ```bash
   DISPLAY=:99 chromium-browser --no-sandbox --headless --dump-dom https://example.com | head -5
   ```

5. Install the agent-browser skill:
   ```bash
   openclaw skill install agent-browser
   ```

6. Add the skill to your agent's configuration:
   ```json
   {
     "skills": ["agent-browser"]
   }
   ```

7. Test it by asking your agent to visit a public website and describe what it sees.

### Expected output

The agent navigates to a website, takes a screenshot artifact, and describes the page content.

### Cookie persistence

The browser stores cookies per agent in `~/.openclaw/skills/agent-browser/cookies/`. This lets agents maintain logged-in sessions across invocations. Cookie expiration is the primary failure mode for any workflow that depends on authenticated browsing. When cookies expire, the agent loses access and needs fresh credentials.

### Common failures

- **"cannot open display":** Xvfb is not running. Check `systemctl status xvfb`.
- **Chromium crashes:** Insufficient memory. The browser needs at least 512 MB free. Check `free -h`.
- **Anti-bot blocks:** Some sites detect headless browsers. The agent-browser skill handles common detection vectors, but aggressive anti-bot systems (Cloudflare, Akamai) may still block access.

### A cautionary note on browsing

Automated browsing carries real risk. During the talk, Mike will share the story of how his LinkedIn agent liked a competitor's post by mistake. The lesson: start with read-only operations. Add write actions (likes, posts, comments) only after you have tested the agent's judgment on dry runs with approval gates.

---

## Section 9: connect Slack (or Telegram / WhatsApp)

**Maps to:** Chapter 3 (channel bindings) and Chapter 5 (flagship demos)

Slack is the primary interface for the production system. 33 channels are bound to agents, each channel serving as a dedicated workspace for a specific function. Telegram and WhatsApp are available as alternatives for simpler setups.

### Steps (Slack)

1. Create a Slack app at api.slack.com/apps.

2. Configure the following OAuth scopes:
   - `channels:read`
   - `channels:history`
   - `chat:write`
   - `reactions:read`
   - `reactions:write`
   - `files:read`
   - `files:write`

3. Install the app to your workspace and copy the Bot User OAuth Token.

4. Configure OpenClaw with the token:
   ```bash
   openclaw config set slack.botToken xoxb-your-token-here
   ```

5. Set up event subscriptions. OpenClaw needs a publicly reachable URL for Slack to send events to. Use Tailscale Funnel:
   ```bash
   sudo tailscale funnel 18789
   ```

6. In the Slack app settings, set the Event Request URL to:
   ```
   https://<your-tailscale-hostname>.ts.net/slack/events
   ```

7. Subscribe to these bot events:
   - `message.channels`
   - `app_mention`

8. Create a Slack channel for your first agent (e.g., `#my-assistant`).

9. Get the channel ID (right-click the channel name, copy link, the ID is at the end).

10. Bind the channel to your agent:
    ```bash
    openclaw channel bind <channel-id> my-assistant --platform slack
    ```

### Steps (Telegram alternative)

1. Create a bot via @BotFather on Telegram.
2. Copy the bot token.
3. Configure: `openclaw config set telegram.botToken <token>`
4. Bind a chat to your agent: `openclaw channel bind <chat-id> my-assistant --platform telegram`

### Steps (WhatsApp alternative)

1. Set up the WhatsApp Business API (requires a Meta Business account).
2. Configure: `openclaw config set whatsapp.token <token>`
3. Bind: `openclaw channel bind <phone-number> my-assistant --platform whatsapp`

### Expected output

Send a message in your Slack channel. The bound agent responds within a few seconds.

### Common failures

- **No response from agent:** Check that the event subscription URL is reachable. Run `curl https://<hostname>.ts.net/slack/events` from outside your network.
- **"not_authed" error:** The bot token is invalid or expired. Regenerate it in the Slack app settings.
- **Funnel not working:** Tailscale Funnel requires a paid plan or a free trial. Run `tailscale funnel status` to check.
- **Agent responds to every message:** Set `requireMention: true` in the channel binding if you want the agent to respond only when @-mentioned.

---

## Section 10: schedule your first cron job

**Maps to:** Chapter 8 (two-box pattern and ops discipline)

Cron jobs turn agents from reactive tools into proactive systems. The production server runs 30 enabled cron jobs covering daily health reports, security sweeps, content ingestion, and weekly digests.

### Steps

1. List existing OpenClaw cron jobs:
   ```bash
   openclaw cron list
   ```

2. Create a daily system health report:
   ```bash
   openclaw cron create \
     --name "Daily Health Report" \
     --schedule "0 6 * * *" \
     --timezone "America/New_York" \
     --agent my-assistant \
     --prompt "Generate a system health report. Check disk usage, memory, CPU load, and the status of all OpenClaw services. Post the report to Slack."
   ```

3. Verify the job was created:
   ```bash
   openclaw cron list
   ```

4. Test it manually:
   ```bash
   openclaw cron run "Daily Health Report"
   ```

5. Check the Slack channel for the report output.

6. Add a second job, a daily system map generation:
   ```bash
   openclaw cron create \
     --name "Daily System Map" \
     --schedule "30 5 * * *" \
     --timezone "America/New_York" \
     --prompt "Run the system-map skill and save the output to the workspace."
   ```

### Expected output

`openclaw cron list` shows your jobs with their schedules. The manual test run produces output in your Slack channel.

### Production examples

The production server runs these categories of cron jobs:

| Category | Examples | Schedule |
|---|---|---|
| System health | Daily health report, daily backup, system map | Daily 5-6 AM |
| Security | AISF daily sweep, source discovery, nightly cleanup | Daily, various |
| Content | YouTube KB ingest, LinkedIn feed monitor | Every 6h / daily |
| Business | Weekly prospect refresh, sales enablement update | Weekly Monday |
| Maintenance | Chrome guardian, VPS monitor | Every 1-2 minutes |

### Common failures

- **Job doesn't fire:** Check the timezone setting. A job scheduled for `0 6 * * *` in `America/New_York` fires at 10:00 UTC during EDT.
- **Job fires but agent errors:** Run it manually with `openclaw cron run` to see the error output.
- **Too many jobs running at once:** Respect the subagent limits. If `maxConcurrent` is set to 2, stagger your cron schedules so no more than 2 jobs overlap.

---

## Section 11: set up ntfy.sh push notifications

**Maps to:** Chapter 8 (two-box pattern and ops discipline)

ntfy.sh is a free, open-source push notification service. No account required. Pick a topic name, publish a message with curl, and it arrives on your phone in seconds. The production system uses ntfy to alert on system events, cron failures, and agent completions.

### Steps

1. Install the ntfy app on your phone:
   - iOS: search "ntfy" in the App Store
   - Android: search "ntfy" in Google Play or F-Droid

2. Open the app and subscribe to a topic. Use something unique to avoid collisions with other users:
   ```
   my-openclaw-alerts
   ```

3. Test from your server:
   ```bash
   curl -d "OpenClaw test notification" ntfy.sh/my-openclaw-alerts
   ```

4. Your phone should buzz within 1-2 seconds.

5. Send richer notifications with headers:
   ```bash
   curl \
     -H "Title: Daily health report complete" \
     -H "Priority: default" \
     -H "Tags: white_check_mark" \
     -d "All 25 agents healthy. Disk at 17%. No errors in the last 24 hours." \
     ntfy.sh/my-openclaw-alerts
   ```

6. Create a helper script for your agents:
   ```bash
   cat > ~/bin/notify <<'EOF'
   #!/bin/bash
   curl -s -H "Title: ${2:-OpenClaw}" -d "$1" ntfy.sh/my-openclaw-alerts
   EOF
   chmod +x ~/bin/notify
   ```

7. Now any agent or cron job can call:
   ```bash
   notify "YouTube KB ingest finished. 14 new transcripts added."
   ```

8. Wire it into your cron jobs. Add a notification to the end of your daily health report:
   ```bash
   openclaw cron create \
     --name "Daily Health Report" \
     --schedule "0 6 * * *" \
     --timezone "America/New_York" \
     --agent my-assistant \
     --prompt "Generate a system health report. Post to Slack, then run: notify 'Health report posted to Slack'"
   ```

### Priority levels

ntfy supports five priority levels: `min`, `low`, `default`, `high`, `urgent`. Use `urgent` sparingly. On most phones it overrides Do Not Disturb.

```bash
# Agent down, wake me up
curl -H "Priority: urgent" -H "Tags: rotating_light" \
  -d "Gateway crashed. Auto-restart failed." \
  ntfy.sh/my-openclaw-alerts
```

### Expected output

A push notification on your phone within 1-2 seconds of the curl command.

### Common failures

- **No notification received:** Check that your topic name matches exactly between the app subscription and the curl command. Topics are case-sensitive.
- **Notifications delayed:** Free tier rate limits apply at high volume. For most OpenClaw setups (tens of notifications per day), you will never hit them.
- **Want privacy:** Self-host ntfy on your own server. It is a single Go binary: `sudo apt install ntfy`, then point your curl commands at `https://<your-tailscale-hostname>:8080`.

---

## Section 12: map a Tailscale shared drive

**Maps to:** Chapter 1 (Linux and Tailscale foundation) and Chapter 8 (two-box pattern)

A shared drive across your Tailscale network lets multiple servers read and write to the same files. The production setup uses this for cross-server configuration sharing, dashboard registries, and artifact handoffs between the canary and production boxes.

### Steps

1. Choose which server will host the shared directory. In this example, your primary VPS:
   ```bash
   sudo mkdir -p /home/openclaw/shared
   sudo chown openclaw:openclaw /home/openclaw/shared
   ```

2. Install Samba on the host server:
   ```bash
   sudo apt install -y samba
   ```

3. Add a Samba share restricted to the Tailscale interface:
   ```bash
   sudo tee -a /etc/samba/smb.conf > /dev/null <<'EOF'

   [openclaw-shared]
     path = /home/openclaw/shared
     browseable = yes
     read only = no
     valid users = openclaw
     interfaces = tailscale0
     bind interfaces only = yes
   EOF
   ```

4. Set the Samba password for the openclaw user:
   ```bash
   sudo smbpasswd -a openclaw
   ```

5. Restart Samba:
   ```bash
   sudo systemctl restart smbd
   ```

6. From a second server on your tailnet, mount the share:
   ```bash
   sudo apt install -y cifs-utils
   sudo mkdir -p /mnt/openclaw-shared
   sudo mount -t cifs //<tailscale-ip>/openclaw-shared /mnt/openclaw-shared \
     -o username=openclaw,password=<your-samba-password>,uid=$(id -u openclaw),gid=$(id -g openclaw)
   ```

7. Verify the mount:
   ```bash
   ls /mnt/openclaw-shared
   echo "test" > /mnt/openclaw-shared/test.txt
   # Check from the host server:
   cat /home/openclaw/shared/test.txt
   ```

8. Make the mount persistent across reboots. Add to `/etc/fstab`:
   ```
   //<tailscale-ip>/openclaw-shared /mnt/openclaw-shared cifs username=openclaw,password=<password>,uid=1000,gid=1000,_netdev 0 0
   ```
   For better security, store credentials in a separate file:
   ```bash
   sudo tee /etc/samba/credentials > /dev/null <<'EOF'
   username=openclaw
   password=<your-samba-password>
   EOF
   sudo chmod 600 /etc/samba/credentials
   ```
   Then reference it in fstab:
   ```
   //<tailscale-ip>/openclaw-shared /mnt/openclaw-shared cifs credentials=/etc/samba/credentials,uid=1000,gid=1000,_netdev 0 0
   ```

### What to put on the shared drive

| Use case | Example |
|---|---|
| Dashboard registry | `dashboards.yaml` listing all running dashboards across servers |
| Cross-server configs | Shared agent templates, skill scaffolds |
| Artifact handoffs | System maps, health reports, backup manifests |
| Shared content | Product blurbs, writing style guides, competitor data |

The production system uses the shared drive at `/home/openclaw/shared/ccode-mgr/` for the dashboard registry that feeds the master command center.

### Expected output

Files written on one server appear on the other within seconds. Both servers can read and write.

### Common failures

- **Mount fails with "connection refused":** Samba is not listening on the Tailscale interface. Check `ss -tlnp | grep 445` and verify the `interfaces = tailscale0` line in smb.conf.
- **Permission denied on write:** The `valid users` setting in smb.conf must match the user you authenticated with `smbpasswd`.
- **Mount disappears after reboot:** The `_netdev` option in fstab tells the system to wait for network before mounting. Without it, the mount fails because Tailscale is not up yet.
- **Slow file access:** Samba over Tailscale adds a small latency hop. For large file transfers, use `rsync` over SSH instead. The shared drive is best for small config files and registries.

### Alternative: Tailscale file sharing (taildrop)

For one-off file transfers between devices, Tailscale has a built-in file sharing feature:
```bash
tailscale file cp myfile.txt <device-name>:
```
This is simpler than Samba but does not give you a persistent shared directory.

---

## Section 13: the cw workflow

**Maps to:** Chapter 2 (the development loop)

The `cw` (claude-workspaces) script manages tmux-backed Claude Code sessions. It lists workspaces, creates new ones with CLAUDE.md scaffolding, attaches by name, and indexes recent sessions. The production version is 46.6 KB of battle-tested bash.

### Steps

1. Clone the repo:
   ```bash
   git clone https://github.com/openclaw-framework.git ~/openclaw-framework
   ```

2. Install the `cw` script:
   ```bash
   sudo cp ~/openclaw-framework/bin/cw /usr/local/bin/cw
   sudo chmod +x /usr/local/bin/cw
   ```

3. Verify the install:
   ```bash
   cw help
   ```

4. List existing workspaces:
   ```bash
   cw list
   ```

5. Create a new workspace:
   ```bash
   cw new my-project
   ```
   This creates a tmux session named `my-project`, sets up a working directory, and scaffolds a CLAUDE.md file.

6. Attach to it:
   ```bash
   cw my-project
   ```

7. Inside the session, launch Claude Code and start working. Detach with `Ctrl-b d`.

8. From your phone, SSH to the server via Tailscale and reattach:
   ```bash
   ssh openclaw@<tailscale-ip>
   cw my-project
   ```

### The three lessons

1. **The session is the unit of work.** Each workspace is a named tmux session with its own Claude Code instance, working directory, and CLAUDE.md context. Close your laptop, walk the dogs, pick it up from your phone.

2. **Naming matters.** `cw list` only helps if your workspace names describe the work. Use project names, ticket numbers, or feature descriptions.

3. **Mobile parity changes how you work.** Once you can SSH from your phone and attach to any workspace, you stop thinking of "at the computer" as a prerequisite for development.

### Common failures

- **tmux not found:** Install it with `sudo apt install -y tmux`
- **"session not found":** The session may have been killed. Run `cw list` to see active sessions, or `cw new` to create a fresh one.
- **SSH from phone is slow:** Install a proper SSH client (Termius, Blink Shell on iOS; JuiceSSH on Android) rather than using a web-based terminal.

---

## Section 14: troubleshooting and where to ask for help

**Maps to:** Chapter 9 (where I'd push back on myself)

### Common system-level issues

| Symptom | Likely cause | Fix |
|---|---|---|
| Agent stops responding | Gateway crashed or API key exhausted | `systemctl status openclaw-gateway`, check API credits |
| High CPU / memory | Runaway subagents or browser processes | Check `maxConcurrent` limit, restart gateway |
| Slack messages not arriving | Event subscription URL unreachable | Verify Tailscale Funnel is running, check Slack app event logs |
| Memory database locked | Concurrent writes | Restart the agent, check for zombie processes |
| Browser skill fails | Xvfb down or cookies expired | `systemctl status xvfb`, refresh cookies |
| Cron job runs but no output | Agent errored silently | Run manually with `openclaw cron run "<name>"` |

### Diagnostic commands

```bash
# Overall system health
openclaw status

# Gateway logs
journalctl -u openclaw-gateway -f

# Agent-specific logs
openclaw agent logs my-assistant --tail 50

# System resources
htop
df -h
free -h

# Tailscale connectivity
tailscale status
tailscale ping <other-device>

# Check all running cron jobs
openclaw cron list --verbose
```

### The honest cost of running this

The production system takes 3-5 hours per week of active use and 1-2 hours per week of tuning and maintenance. The API cost runs about $100/month depending on workload. The server costs roughly $30/month.

Things that break most often:
- Browser cookie expiration (single point of failure for authenticated browsing workflows)
- Model provider rate limits during high-concurrency periods
- Slack API changes that break event subscriptions

### What to do differently if starting from scratch

Three things the production system learned the hard way:

1. **Move to systemd services early.** Cron-only orchestration works until you have 30 jobs. Systemd gives you logging, restart policies, and dependency ordering for free.

2. **Set per-agent allowlists from day one.** The production server has 119 permission rules. That number grew reactively after agents did things they should not have. Start restrictive.

3. **Enable exec approvals immediately.** Human-in-the-loop approval for destructive commands prevents the kind of mistakes that erode trust in the system.

### Where to get help

- **GitHub repo:** [github.com/openclaw-framework](https://github.com/openclaw-framework) (issues and discussions)
- **During the talk:** Ask questions at any point. The session is interactive.
- **After the talk:** Reach out to Mike directly via Slack or email (shared on the closing slide).

---

*You own the config, you own the exit.*

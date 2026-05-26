# Authenticated web browsing for your agents

This is what lets your agents browse the web as *you* — logged into YouTube, LinkedIn, Google, and any other site where you have a session. There are three layers to set up.

---

## Layer 1: Exit node (route traffic through your home IP)

Your VPS has a data center IP that many websites flag or block. Tailscale exit nodes let you route your server's web traffic through your home machine so websites see your residential IP instead.

### Setup

1. On your home machine (Windows or Mac), open Tailscale and enable **"Run as exit node"**
   - **Windows:** Right-click the Tailscale tray icon → Exit Node → "Run as exit node"
   - **Mac:** Click the Tailscale menu bar icon → Preferences → toggle "Run as exit node"

2. In the Tailscale admin console ([login.tailscale.com/admin](https://login.tailscale.com/admin)), approve the exit node under the machine's settings

3. On your server, route traffic through it:
   ```bash
   sudo tailscale set --exit-node=<your-home-machine-tailscale-ip>
   ```

4. Verify:
   ```bash
   curl ifconfig.me
   ```
   This should show your home IP, not the VPS IP.

### Why this matters

Without an exit node, your agents browse from a data center IP. Sites like LinkedIn, YouTube, and Google are more likely to challenge or block data center IPs. Routing through your home machine gives you a clean residential IP that these sites trust.

---

## Layer 2: Agent-browser (headless Chrome with persistent profiles)

`agent-browser` is an npm package that gives your agents a real Chrome browser with persistent cookie storage. Each profile keeps its own cookies, localStorage, and session data across runs.

The bootstrap script installs agent-browser automatically. If you need to install it manually:

```bash
npm install -g agent-browser
```

### Profiles

Profiles live in `~/.agent-browser/profiles/`. Create one per identity:

| Profile name | Purpose |
|---|---|
| `youtube` | Your Google/YouTube session |
| `linkedin-mike` | Your LinkedIn session |
| `openclaw-default` | Throwaway for public unauthenticated browsing |

Never share a profile across different accounts or identities. Each profile is a credential container.

---

## Layer 3: Cookie import

This is the key step. You export cookies from your personal browser and import them into an agent-browser profile on the server. This gives the agent your authenticated session without ever typing your password on the server.

### Method 1: Export from your browser (laptop)

1. Install the **Cookie-Editor** browser extension in Chrome or Firefox on your laptop
   - Chrome: search "Cookie-Editor" in the Chrome Web Store
   - Firefox: search "Cookie-Editor" in Firefox Add-ons

2. Navigate to the site you want (e.g., youtube.com while logged in)

3. Click the Cookie-Editor icon → **Export** → **JSON** → copy to clipboard

4. Save the JSON to a file on your server (e.g., `~/youtube-cookies.json`)

5. Import into the agent-browser profile:
   ```bash
   import-cookies --profile youtube --from ~/youtube-cookies.json
   ```

6. Verify it works:
   ```bash
   agent-browser --profile ~/.agent-browser/profiles/youtube --args --no-sandbox open https://youtube.com
   agent-browser wait --load networkidle
   agent-browser snapshot
   # You should see your logged-in YouTube homepage
   agent-browser close
   ```

### Method 2: Send cookies via Slack, WhatsApp, or Telegram

If your server has a messaging channel connected, you can import cookies without SSH:

1. Export cookies from Cookie-Editor on your laptop (JSON format, copy to clipboard)

2. Paste the JSON directly into your agent's Slack channel (or WhatsApp/Telegram) with a message like:

   > Import these cookies into the youtube profile:
   > ```
   > [{"name":"SID","value":"...","domain":".google.com",...}, ...]
   > ```

3. Your agent saves the JSON to a temp file and runs:
   ```bash
   import-cookies --profile youtube --from /tmp/cookies.json --clear-existing
   ```

This is useful for refreshing expired cookies from your phone or laptop without needing to SSH into the server.

### Method 3: Netscape format (for yt-dlp)

Some tools like `yt-dlp` use Netscape/curl format cookies instead of JSON. Cookie-Editor can export in this format too.

1. In Cookie-Editor, export as **Netscape** format
2. Save as `cookies.txt` in the appropriate location:
   ```bash
   # For YouTube KB skill
   cp ~/cookies.txt ~/.openclaw/skills/youtube-kb/cookies.txt
   ```

---

## When cookies expire

Cookies expire (typically every 30-90 days depending on the site). When they do, the agent gets redirected to a login page and stops working.

The `browser-core` skill detects this automatically — if the URL contains `login`, `signin`, or `authwall` after navigating, it exits with code 2 (session expired).

When this happens:

1. Log in to the site on your laptop
2. Re-export cookies with Cookie-Editor
3. Re-import on the server (via SSH or by pasting into your Slack/WhatsApp channel)

```bash
import-cookies --profile youtube --from ~/fresh-cookies.json --clear-existing
```

The `--clear-existing` flag removes old cookies for a clean import.

---

## Managing profiles

List cookies in a profile:
```bash
import-cookies --profile youtube --list
```

List cookies for a specific domain:
```bash
import-cookies --profile youtube --list --domain google.com
```

Import only cookies for a specific domain:
```bash
import-cookies --profile youtube --from ~/cookies.json --domain .youtube.com
```

---

## Quick reference

| Command | What it does |
|---|---|
| `agent-browser --version` | Verify agent-browser is installed |
| `import-cookies --profile NAME --from FILE` | Import cookies into a profile |
| `import-cookies --profile NAME --list` | List cookies in a profile |
| `import-cookies --profile NAME --from FILE --clear-existing` | Replace all cookies |
| `agent-browser --profile PATH --args --no-sandbox open URL` | Open a URL in a profile |
| `agent-browser snapshot` | Get the current page accessibility tree |
| `agent-browser screenshot ~/screenshot.png` | Take a screenshot |
| `agent-browser close` | End the browser session |

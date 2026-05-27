# First research project setup (for Claude Code)

**These instructions are for Claude Code to follow.** When a user pastes this into a `cw` workspace, execute these steps in order. Pause and ask the user when input is needed.

## What this builds

A daily research pipeline that:
- Searches the web via Brave API for a topic the user specifies
- Monitors YouTube channels for new videos
- Stores results in a QMD (Query Memory Database) SQLite database
- Publishes a dashboard on the Tailscale network with latest results
- Runs automatically on a daily schedule via OpenClaw cron

---

## Step 1: Verify prerequisites

Run each of these and confirm they pass. If any fail, fix them before continuing.

```bash
openclaw --version              # OpenClaw installed
openclaw status                 # Gateway running
agent-browser --version         # agent-browser installed
tailscale status                # Tailscale connected
openclaw infer web providers    # Web search providers (need Brave)
```

If the gateway is not running:
```bash
nohup openclaw gateway --foreground &>/dev/null &
```

If Brave is not listed as a web provider, tell the user:
> "Brave Search API is not configured. You need a Brave API key from https://brave.com/search/api/ — paste it here and I'll configure it."

Then configure it with `openclaw configure` or the appropriate `openclaw config set` command.

## Step 2: Set up QMD

Check if QMD is already configured:

```bash
openclaw config get memory.backend
```

If it's not set to `qmd`, configure it:

```bash
openclaw config set memory.backend qmd
```

Verify QMD is working by checking the docs reference:
- QMD uses SQLite under the hood
- Data lives in the OpenClaw state directory
- See https://docs.openclaw.ai/concepts/memory-qmd for details

Run `openclaw doctor --fix` to ensure everything is wired up.

## Step 3: Import YouTube cookies

**This step requires user input.** Tell the user:

> "I need YouTube cookies so I can browse YouTube as you. On your laptop browser:
> 1. Install the Cookie-Editor extension (https://cookie-editor.com)
> 2. Go to youtube.com (make sure you're logged in)
> 3. Click the Cookie-Editor icon and click 'Export' (JSON format)
> 4. Paste the JSON here"

Once the user pastes the cookies, import them:

```bash
import-cookies youtube
```

Paste the JSON when prompted. Then verify it works:

```bash
agent-browser browse --profile youtube "https://www.youtube.com"
```

If the page loads with the user's account visible, cookies are working.

## Step 4: Configure search targets

Ask the user what they want to research. They should provide:
1. **Web search queries** — topics to search via Brave (e.g., "1931 Ford roadster")
2. **YouTube channels** — URLs to monitor for new videos

Create a config file in the workspace for the research targets:

```bash
cat > research-config.json << 'CONF'
{
  "web_searches": [
    "1931 Ford roadster"
  ],
  "youtube_channels": [
    {"name": "Jay Leno's Garage", "url": "https://www.youtube.com/@jaylenosgarage"},
    {"name": "AC Designs Garage", "url": "https://www.youtube.com/@ACDesignsGarage"},
    {"name": "Lafontaine Classic Cars", "url": "https://www.youtube.com/@LafontaineClassicCars"}
  ],
  "schedule": "0 8 * * *",
  "dashboard_port": null
}
CONF
```

The user can customize these values. The schedule defaults to 8am daily.

## Step 5: Create the research collector script

Build a script that:
1. Runs Brave web searches for each query in the config
2. Browses each YouTube channel page with agent-browser using the "youtube" profile
3. Extracts video titles, dates, URLs, and descriptions
4. Stores results in QMD with tags for the project
5. Outputs a JSON summary of what was found

Use `openclaw infer web search` for Brave queries. Use `agent-browser` with the youtube profile for channel scraping.

Store all results with QMD memory entries tagged with the project name and date.

## Step 6: Build the dashboard

Create a single-file HTML dashboard (dark theme, responsive) that:
- Shows the latest web search results grouped by query
- Shows the latest YouTube videos grouped by channel
- Displays the date of last update
- Auto-refreshes every 30 minutes
- Serves from a local port on the Tailscale IP

The dashboard should read from a JSON file that the collector script updates.

Pick the next available port by checking:
```bash
cat /home/openclaw/shared/ccode-mgr/dashboards.yaml
```

Bind the server to the Tailscale IP (check with `tailscale ip -4`).

Create a systemd service for the dashboard (see existing services as examples):
```bash
ls /etc/systemd/system/openclaw-*.service
```

Register the dashboard in `/home/openclaw/shared/ccode-mgr/dashboards.yaml`.

## Step 7: Set up the daily cron job

Use OpenClaw cron to schedule the collector:

```bash
openclaw cron add \
  --name "daily-research" \
  --schedule "0 8 * * *" \
  --command "<collector script path>"
```

Verify the cron is registered:
```bash
openclaw cron list
```

Do a test run:
```bash
openclaw cron run daily-research
```

## Step 8: Verify end-to-end

1. Run the collector manually and confirm results appear in QMD
2. Confirm the dashboard loads at `http://<tailscale-ip>:<port>`
3. Confirm the cron job is scheduled
4. Report the dashboard URL and cron schedule to the user

Tell the user:
> "Research project is live. Dashboard at http://<tailscale-ip>:<port>. Daily updates run at 8am. You can run `openclaw cron run daily-research` anytime for an immediate refresh."

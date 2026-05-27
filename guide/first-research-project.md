# First research project setup (for Claude Code)

**These instructions are for Claude Code to follow.** When a user pastes this into a `cw` workspace, execute these steps in order. Pause and ask the user when input is needed.

## What this builds

A daily research pipeline that:
- Searches the web via Brave API for a topic the user specifies
- Monitors YouTube channels for new videos via agent-browser
- Stores results in SQLite + QMD (Query Memory Database)
- Publishes a dashboard on the Tailscale network with latest results
- Runs automatically on a daily schedule via OpenClaw cron

### Inputs needed from the user

1. **Research topic** — drives the Brave search queries
2. **YouTube channels to monitor** — channel URLs
3. **YouTube cookies** — exported from a logged-in browser via Cookie-Editor as JSON
4. **Schedule** — defaults to `0 8 * * *` (8am daily)

---

## Step 0: Verify prerequisites

Run each of these and confirm they pass:

```bash
openclaw --version                                    # OpenClaw installed
openclaw gateway status                               # Gateway running
agent-browser --version                               # agent-browser installed
tailscale status                                      # Tailscale connected
openclaw infer web providers | jq '.search[]'         # Brave must be selected:true
```

If the gateway is not running:
```bash
nohup openclaw gateway >> /tmp/openclaw-gateway.log 2>&1 &
```

If Brave is not listed or not selected, tell the user:
> "Brave Search API is not configured. You need a Brave API key from https://brave.com/search/api/ — paste it here and I'll configure it."

Then configure it with `openclaw configure`.

## Step 1: Install QMD and switch memory backend

QMD ships as a separate npm package:

```bash
sudo npm install -g @tobilu/qmd
qmd --version
openclaw config set memory.backend qmd
mkdir -p ~/.openclaw/agents/main/qmd/xdg-cache/qmd
openclaw memory index
openclaw memory status | head -5    # Provider should now show "qmd"
```

Restart the gateway after the config change (kill + relaunch).

## Step 2: Import YouTube cookies

**This step requires user input.** Tell the user:

> "I need YouTube cookies so I can browse YouTube as you. On your laptop browser:
> 1. Install the Cookie-Editor extension (https://cookie-editor.com)
> 2. Go to youtube.com (make sure you're logged in)
> 3. Click the Cookie-Editor icon and click 'Export' (JSON format)
> 4. Paste the JSON here"

### Launch agent-browser with --no-sandbox

The bundled Chrome on Ubuntu requires `--no-sandbox` on first launch. If a daemon is already running, `--args` is silently ignored — close it first:

```bash
agent-browser close 2>/dev/null || true
agent-browser --args "--no-sandbox" --session-name youtube-research open https://www.youtube.com
```

### Transform Cookie-Editor JSON to CDP format

Cookie-Editor JSON cannot be imported as-is. CDP rejects `sameSite: "unspecified"` / `"no_restriction"`, expects integer `expires`, and trips on `id/storeId/hostOnly/session` fields. Transform first:

```bash
mkdir -p secrets && chmod 700 secrets
# Save the user's pasted cookies to secrets/youtube-cookies.json (mode 600)
```

```python
# Transform script:
import json
ss = {'no_restriction':'None','strict':'Strict','lax':'Lax','no restriction':'None','unspecified':None}
raw = json.load(open('secrets/youtube-cookies.json'))
out = []
for c in raw:
    item = {k:c[k] for k in ('name','value','domain','path') if k in c}
    item['secure'] = bool(c.get('secure', False))
    item['httpOnly'] = bool(c.get('httpOnly', False))
    s = ss.get(str(c.get('sameSite','')).lower())
    if s: item['sameSite'] = s
    if 'expirationDate' in c: item['expires'] = int(c['expirationDate'])
    out.append(item)
json.dump(out, open('secrets/youtube-cookies.cdp.json','w'), indent=2)
```

```bash
chmod 600 secrets/youtube-cookies.*.json
agent-browser --session-name youtube-research cookies set --curl secrets/youtube-cookies.cdp.json
```

Verify cookies work:

```bash
agent-browser --session-name youtube-research open https://www.youtube.com/feed/library
agent-browser --session-name youtube-research --json eval \
  "document.querySelector('button[aria-label*=Account]')?.getAttribute('aria-label')"
# expect: "Account menu"
```

## Step 3: Create workspace layout and config

```bash
mkdir -p collector dashboard data logs secrets
```

Create `research-config.json` (single source of truth). Customize the topic, queries, and channels based on what the user asked for:

```json
{
  "project": "research-project",
  "topic": "user's topic here",
  "schedule": "0 8 * * *",
  "searchQueries": [
    "main query",
    "query variation 1",
    "query variation 2"
  ],
  "searchLimit": 10,
  "youtubeChannels": [
    {"handle": "@channelHandle", "url": "https://www.youtube.com/@channelHandle/videos"}
  ],
  "youtubeVideosPerChannel": 12,
  "browserSession": "youtube-research",
  "qmdTag": "research-project",
  "paths": {
    "db": "data/research.sqlite",
    "dashboard": "dashboard/index.html",
    "log": "logs/collector.log"
  },
  "dashboard": { "bind": "0.0.0.0", "port": null, "refreshMinutes": 30 }
}
```

Pick the dashboard port by checking existing registrations:
```bash
cat /home/openclaw/shared/ccode-mgr/dashboards.yaml 2>/dev/null
```

## Step 4: Build the collector script

Create `collector/collect.py` (~280 lines Python) that does:

1. **Brave web search** — For each query in `searchQueries`, call:
   ```bash
   openclaw infer web search --json --provider brave --limit N --query "..."
   ```
   Parse `outputs[*].result.results[]`. **Important:** titles and descriptions are wrapped in `<<<EXTERNAL_UNTRUSTED_CONTENT id="...">>> ... <<<END_EXTERNAL_UNTRUSTED_CONTENT>>>` — strip both delimiters with regex before storing.

2. **YouTube channel scraping** — For each channel, drive agent-browser:
   - `open <channel/videos>` with the `youtube-research` session
   - Wait for page load, scroll 3x to load more videos
   - Run a single `eval` that walks the DOM and extracts video data

   **YouTube DOM selectors (2026-05 layout):**
   - Card element: `yt-lockup-view-model` (legacy fallback: `ytd-rich-item-renderer`, `ytd-grid-video-renderer`)
   - Title link: `a.ytLockupMetadataViewModelTitle` (fallback: `a#video-title-link`, `a#video-title`)
   - Title text: `h3[title]` attribute
   - Duration: `.ytBadgeShapeText`
   - Views/published: first two `.ytContentMetadataViewModelMetadataText` spans

3. **SQLite storage** — Persist into `data/research.sqlite` with tables `web_results`, `youtube_videos`, `runs`. Use `INSERT OR IGNORE` so reruns are idempotent.

4. **QMD indexing** — Write one Markdown file per item into `~/.openclaw/workspace/memory/research/<project>/` so QMD indexes them. Call `openclaw memory index` after writing.

5. **Dashboard regeneration** — Re-render `dashboard/index.html` from the current DB contents.

Smoke test:
```bash
python3 collector/collect.py
# Expect per-query hit counts and a final summary line
```

## Step 5: Build the dashboard

Create `dashboard/index.html` — a single-file HTML dashboard:
- Dark theme, responsive layout
- Web results grouped by query
- YouTube videos grouped by channel with thumbnails and metadata badges
- Footer with last-run summary and timestamp
- `<meta http-equiv="refresh" content="1800">` for auto-refresh every 30 minutes

The collector regenerates this file on each run from the SQLite database.

Create `dashboard/serve.py` — a minimal static HTTP server:
- Bind to `0.0.0.0` on the configured port
- Set `Cache-Control: no-store` headers
- Serve the `dashboard/` directory

Run and verify:
```bash
nohup python3 dashboard/serve.py >> logs/dashboard.log 2>&1 &
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:<port>/index.html         # 200
curl -s -o /dev/null -w "%{http_code}\n" http://$(tailscale ip -4):<port>/index.html # 200
```

Register in `/home/openclaw/shared/ccode-mgr/dashboards.yaml` if it exists.

## Step 6: Schedule with OpenClaw cron

**Important:** `openclaw cron` only schedules agent turns — there is no `--command` flag. Wrap the script execution in an agent message:

```bash
openclaw cron add \
  --name <project>-daily \
  --cron "0 8 * * *" \
  --tz "America/New_York" \
  --message "Run the research collector: execute \`python3 /path/to/collector/collect.py\` and report the final log line as the result." \
  --tools exec \
  --light-context \
  --no-deliver \
  --session isolated \
  --timeout-seconds 900 \
  --description "Brave + YouTube collector for the research project"
```

Verify:
```bash
openclaw cron list
openclaw cron status
openclaw cron run <job-id>     # manual fire for debugging
openclaw cron runs <job-id>    # history
```

## Step 7: Validate end-to-end

```bash
sqlite3 data/research.sqlite \
  "SELECT 'web', COUNT(*) FROM web_results; \
   SELECT 'yt',  COUNT(*) FROM youtube_videos; \
   SELECT run_id, status, web_count, youtube_count FROM runs;"
curl -s -o /dev/null -w "%{http_code}\n" http://$(tailscale ip -4):<port>/index.html
openclaw cron list | grep <project>-daily
```

Tell the user:
> "Research project is live. Dashboard at http://<tailscale-ip>:<port>. Daily updates run at 8am Eastern. Run `openclaw cron run <job-id>` anytime for an immediate refresh."

---

## Known gotchas

These were discovered during live testing. Claude Code should handle them proactively:

- **Cookie-Editor JSON is not CDP-shaped.** `agent-browser cookies set --curl` fails on raw Cookie-Editor JSON. The `sameSite: "unspecified"` value and float `expirationDate` fields must be transformed first (see Step 2).
- **Chrome sandbox.** `agent-browser` fails with `No usable sandbox!` on Ubuntu hosts where unprivileged user namespaces are restricted. Always launch with `--args "--no-sandbox"`. Must `agent-browser close` first if a daemon is already running — `--args` is silently ignored on a running daemon.
- **YouTube DOM changes.** The `a#video-title-link` selector returns 0 matches on new `yt-lockup-view-model` cards even though `a[href*="/watch?v="]` finds hits (most are thumbnail anchors with no title text). Always read the actual lockup HTML when selectors return 0.
- **Brave wraps text in untrusted-content markers.** `<<<EXTERNAL_UNTRUSTED_CONTENT>>>` wrappers appear around title/description fields. Strip with regex before storing or they appear verbatim on the dashboard.
- **QMD ships separately.** `memory.backend = qmd` errors with `spawn qmd ENOENT` until you `sudo npm install -g @tobilu/qmd` and create the cache directory.
- **`openclaw cron` is agent-only.** No `--command` flag exists. Wrap shell commands in `--message "...exec..."` with `--tools exec`.
- **`openclaw cron list` vs `cron status`.** `list` shows human-readable next-run, but the epoch timestamp is in `cron status` output (`nextWakeAtMs`).

## Expected file layout after setup

```
<project>/
├── CLAUDE.md
├── research-config.json
├── collector/
│   └── collect.py
├── dashboard/
│   ├── index.html              # regenerated each run
│   └── serve.py
├── data/
│   └── research.sqlite
├── logs/
│   ├── collector.log
│   └── dashboard.log
└── secrets/
    ├── youtube-cookies.json     # Cookie-Editor raw, mode 600
    └── youtube-cookies.cdp.json
```

Plus state outside the workspace:
- `~/.openclaw/openclaw.json` — `memory.backend = "qmd"`
- `~/.openclaw/cron/jobs.json` — contains the daily cron job
- `~/.openclaw/agents/main/qmd/xdg-cache/qmd/index.sqlite` — QMD index
- `~/.openclaw/workspace/memory/research/<project>/*.md` — per-item QMD docs

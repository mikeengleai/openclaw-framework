# Operating your OpenClaw server

Your server is set up, the gateway is running, and your first hatch is complete. Now what? This guide covers the daily tools and patterns that make an OpenClaw server useful: managing workspaces, controlling sessions from your phone, building agents from APIs, and turning web data into dashboards.

---

## 1. Claude Workspaces (`cw`)

The single most useful tool on your server is `cw`, a workspace manager that keeps all your Claude Code sessions organized. As Mike put it during the walkthrough: "I wrote this tool called Claude Workspaces. And it just shows you all the things you're working on."

Type `cw` at the command line with no arguments and you get an interactive menu. It lists every workspace on the server, shows which ones are running, and lets you create new ones, stop old ones, or rotate bloated sessions. To create a new workspace, select `[n]` from the menu, give it a short name and a description, and you're dropped straight into a Claude Code session scoped to that topic. To resume a workspace you left running, just type `cw sales` or `cw research` directly from the shell. The tool looks up the matching tmux session and reattaches you.

Every workspace lives under `~/workspaces/<name>/` and gets its own `CLAUDE.md` file, memory directory, and session history. This isolation matters. Your sales workspace doesn't bleed context into your security research, and your peptide project doesn't confuse your infrastructure work. When a session gets too long and Claude starts losing context, you rotate it with `cw rotate <name>`. That compacts the memory files, generates a HANDOFF.md document summarizing everything in flight, archives the old session, and launches a fresh one seeded with that handoff.

The HANDOFF.md pattern is worth understanding. When you start a fresh session in a workspace that contains a HANDOFF.md file, `cw` automatically detects it and feeds it to Claude as the opening context. The new session reads the handoff, absorbs the decisions, file paths, and open threads from the previous session, and picks up where you left off. You never have to re-explain your project from scratch. Other useful commands: `cw stop <name>` kills a running session, `cw delete <name>` removes a workspace entirely (with confirmation), `cw compact <name>` curates the memory files without doing a full rotation.

---

## 2. `/remote-control`: manage from anywhere

Once you're inside a Claude Code session, type `/remote-control` and a web interface opens on your Tailscale network. Mike demonstrated this live: "It just popped up here, and this is my web interface into this server. Where I can be out here on my phone." You can send commands, read output, and manage your server from a browser on any device that's on your Tailscale network.

The key insight is persistence. When Mike closed his browser during the demo, he pointed out: "If I close this, it's running in the background on the server." The Claude Code session keeps executing. You can check in from your phone at lunch, paste a new instruction, close the browser, and come back later to see the results. This is how you manage a server that runs 30 daily jobs across dozens of Slack channels without needing to SSH in from every location.

The `/remote-control` command is typed inside a running Claude Code session, not at the bash prompt. It binds to your server's Tailscale IP, so only devices on your private network can reach it. If you want to use it while away from your desk, make sure your phone is connected to Tailscale. The combination of `cw` for session management and `/remote-control` for browser access means you can manage your entire OpenClaw server from a phone screen. Start a workspace in the morning, let it run background tasks all day, check the results from your phone in the evening, and rotate the session when it gets stale.

---

## 3. Superpowers: your first skill

If you ran `post-onboard.sh` during setup, you already have the Superpowers plugin installed (via `claude plugins add https://github.com/obra/superpowers`). This plugin adds a set of professional development skills that replace freestyling with structured workflows.

The most immediately useful skill is brainstorming. Before you build anything, the brainstorming skill walks you through intent, requirements, and design decisions. Instead of jumping straight to code and ending up three iterations deep in the wrong direction, you spend two minutes clarifying what you actually want. The TDD (test-driven development) skill flips the usual order: write the test first, watch it fail, then implement. This sounds tedious until you realize the agent writes both the test and the implementation for you. You just confirm the test captures what you meant.

The debugging skill is systematic rather than guess-and-check. When something breaks, it walks through reproduction, isolation, and root-cause analysis before proposing a fix. The verification skill prevents a common failure mode where the agent claims something works without actually checking. It requires running the verification commands and confirming the output before making success claims.

Think of Superpowers as the difference between handing someone a blank terminal and handing them a workbench with labeled tools. The agent still does the work, but the skills impose structure that catches mistakes earlier. You can see all available skills by asking Claude "what skills do you have?" inside any session. Each skill triggers automatically based on what you're doing, or you can invoke them explicitly.

---

## 4. Building an agent from an API

One of the most practical things you can do with an OpenClaw server is wrap an external API into a conversational agent and share it with your team via Slack. Mike demonstrated this with Constella, a dark web monitoring service: "I just created an agent in OpenClaw, I said, here's an API key, and here's their API documentation. Create an interface and link it to Slack. It took me less than 10 minutes."

The pattern is straightforward. First, get an API key from the service you want to integrate. Second, find their API documentation. If the documentation is publicly accessible, your agent can read it directly and learn all the available endpoints and parameters. If the documentation is gated behind a login, you'll need to scrape or download it and provide it as a local file. Third, tell your Claude Code session what you want: describe the API, point it at the docs, and ask it to build an interface connected to a Slack channel. The agent writes the integration code, sets up the Slack connection, and you're done.

The result is that your team can interact with the API through natural language in Slack. Mike gave the Constella agent to his product team and "they had all they needed to try it out. They didn't have to go run Postman or create scripts, or learn what the APIs do." This is the real value: turning a technical API into something anyone on the team can use by just typing a question in Slack.

One thing to watch for is gated documentation. As Mike noted, "sometimes their documentation is gated, and the agent can't get to it, so you just have to figure out how to scrape it." If the agent can't browse to the docs page, download the documentation yourself (PDF, HTML, or plain text) and drop it into the workspace directory where the agent can read it.

---

## 5. The research pipeline: from web to dashboard

The research pipeline is where everything clicks together. The data flow runs like this: Brave Search and YouTube provide raw data, the collector script processes and stores it in SQLite and QMD, a dashboard renders the current state as a web page on your Tailscale network, and OpenClaw cron triggers the whole cycle on a schedule. Notifications go to Slack so you know when new results arrive.

Mike showed this running live with an AI security research project: "522 entries that have been scraped over the past month, with 244 active stories." The pipeline tracked competitors, monitored industry developments, and surfaced new articles across dozens of topics. Every day, the agent went out to the web and YouTube, pulled back new entries, and updated the dashboard. The nightly synthesis found new entries, identified new stories, and flagged escalations, all delivered to Slack automatically.

The dashboard side is just as fast to set up. Mike showed a visualization of his security research data grouped by topic (runtime security, agentic identity, agent authorization) and said: "It took me 3 minutes to create this visualization. I just told it to do it, and it did it." The dashboards are single-file HTML pages served on your Tailscale network. Anyone on your network can see them from any device.

For the complete technical walkthrough of setting up your own research pipeline, including Brave API configuration, YouTube cookie handling, QMD indexing, and cron scheduling, see [first-research-project.md](first-research-project.md). That guide covers every step from prerequisites to end-to-end validation.

---

## 6. QMD: your agent's memory

QMD (Query Markdown) is the database layer that makes persistent research possible. It was created by Toby, the founder of Stripe, who got into OpenClaw and built a way to manage Markdown files with SQLite-backed indexing. Mike described it simply: "It's almost like a Postgres database or a SQL database, but it runs all locally, it's very fast, and it supports indexing and everything."

Without QMD, you end up with markdown files scattered everywhere. Every agent session creates notes, summaries, and research artifacts, and without a database backing them, they just pile up in directories with no way to search or cross-reference. QMD organizes those markdown files into queryable collections with vector search, so when an agent needs to find something it wrote three weeks ago, it can look it up instantly instead of scanning hundreds of files.

The scale Mike is running gives you a sense of what's possible: 9 databases across different domains (security research, peptides, infrastructure documentation), 36 skills, 25 agents, and 30 daily cron jobs feeding data into those databases. The research pipeline described in the previous section stores every scraped article and YouTube transcript as a QMD entry. That's how you get from "I want to track AI security news" to "522 indexed entries with topic clustering and daily synthesis" in a matter of weeks.

For enterprises evaluating this architecture, QMD is where the conversation about data governance starts. During the session, the group discussed how QMD files become critical assets: they contain proprietary research, competitive intelligence, and operational knowledge. There have been attacks where people modified QMD files maliciously. As one participant noted, "there could be 5 QMDs, and we don't know where they are." If you're running this in a corporate environment, treat your QMD databases the way you'd treat any sensitive data store. Lock down file permissions, back up regularly, and know which agents have write access to which databases.

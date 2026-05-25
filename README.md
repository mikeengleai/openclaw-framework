# OpenClaw Framework

A workspace management layer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Run multiple isolated Claude sessions on a single server, rotate context when sessions get long, and keep a clean handoff between rotations.

## What this gives you

- **Workspaces** — each topic gets its own directory, Claude memory, and session history
- **Rotation** — when a session accumulates too much context, rotate it: compact memory, generate a handoff document, archive the old session, and launch a fresh one that picks up where you left off
- **Memory compaction** — a curator pass that deduplicates and tightens your Claude memory files without losing facts
- **Handoff generation** — auto-generates a structured HANDOFF.md from the outgoing session so the new session has full context
- **Archive management** — old sessions are stored under `.archive/` with metadata; restore or purge at will

## Prerequisites

- Python 3.10+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- tmux (optional, for background session management)

## Install

```bash
# Clone the repo
git clone https://github.com/mikeengleai/openclaw-framework.git
cd openclaw-framework

# Copy the workspace manager to your PATH
cp claude-workspaces ~/bin/claude-workspaces
chmod +x ~/bin/claude-workspaces
ln -s ~/bin/claude-workspaces ~/bin/cw

# Copy the compaction prompt
cp compaction-prompt.md ~/bin/compaction-prompt.md

# Create your workspaces directory
mkdir -p ~/workspaces
```

## Quick start

```bash
# Launch the interactive menu
cw

# Create a workspace
cw create myproject "Building a web scraper"

# Launch it
cw launch myproject

# When the session gets long, rotate it
cw rotate myproject
```

## Commands

### Core

| Command | Description |
|---|---|
| `cw` | Interactive menu |
| `cw launch NAME` | Launch or reattach to a workspace |
| `cw list` | List workspaces and their status |
| `cw create NAME [DESC]` | Create a new workspace |
| `cw rename OLD NEW` | Rename a workspace |
| `cw stop NAME` | Stop a running tmux session |
| `cw delete NAME` | Delete a workspace (confirms first) |

### Launch flags

| Flag | Effect |
|---|---|
| `--tmux` | Run inside a tmux session |
| `--bg` | Run in background (agent view, visible in claude.ai) |
| `--fresh` | Start a new session (auto-seeds HANDOFF.md if present) |
| `--seed FILE` | Use FILE as the initial prompt (implies --fresh) |
| `--session ID` | Resume a specific Claude session by ID |

### Memory compaction

| Command | Description |
|---|---|
| `cw compact NAME` | Stage a compacted version of memory (dry-run) |
| `cw compact NAME --apply` | Apply the staged compaction |
| `cw compact NAME --discard` | Throw away the staged version |
| `cw compact NAME --undo` | Restore from the most recent backup |

### Rotation and archival

| Command | Description |
|---|---|
| `cw rotate NAME` | Full rotation: compact + handoff + archive + fresh launch |
| `cw handoff NAME --from-jsonl` | Generate HANDOFF.md from the last session |
| `cw handoff NAME --adopt FILE` | Use an existing markdown as the handoff |
| `cw archive list` | Show archived workspaces |
| `cw archive restore ID` | Restore an archived workspace |
| `cw purge [--older-than Nd]` | Delete old archives |

## File layout

```
~/workspaces/
  myproject/
    CLAUDE.md          # Project instructions for Claude
    HANDOFF.md         # Context bridge between rotations
    LINEAGE.md         # Rotation history
  .archive/
    myproject-20260524-143000/
      workspace/       # Archived workspace files
      project/         # Archived Claude project dir
      rotation-meta.json
```

## How rotation works

1. You are deep in a session and hitting context limits
2. Run `cw rotate myproject`
3. The tool compacts your memory files (dedup, tighten, remove stale entries)
4. Generates a HANDOFF.md summarizing everything in flight
5. Archives the old workspace and Claude project directory
6. Creates a fresh workspace with the same name, carrying forward CLAUDE.md, compacted memory, and HANDOFF.md
7. Launches a new Claude session seeded with the handoff

The new session starts with full context of what was happening, without the bloated conversation history.

## License

Apache 2.0. See [LICENSE](LICENSE).

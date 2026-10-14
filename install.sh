#!/usr/bin/env bash
# install.sh — Install OpenClaw Framework tools from this repo into ~/bin.
# Called by Claude Code as part of the server setup process.
#
# Usage: ~/openclaw-framework/install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/bin"

echo "Installing OpenClaw Framework from $REPO_DIR"
echo

# 1. Ensure ~/bin exists and is on PATH
mkdir -p "$BIN_DIR"
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  SHELL_RC="$HOME/.bashrc"
  [[ -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.zshrc"
  echo "export PATH=\"\$HOME/bin:\$PATH\"" >> "$SHELL_RC"
  export PATH="$BIN_DIR:$PATH"
  echo "  Added ~/bin to PATH in $(basename "$SHELL_RC")"
fi

# 2. Install claude-workspaces (cw) and its compaction prompt from their own repo,
#    https://github.com/mikeengleai/claude-workspaces. Its installer runs cw's tests
#    against the installed copy and links ~/bin/cw, ~/bin/claude-workspaces and
#    ~/bin/compaction-prompt.md. Re-running this script upgrades it.
CW_REPO="$HOME/tools/claude-workspaces"
if [[ -d "$CW_REPO/.git" ]]; then
  git -C "$CW_REPO" pull --ff-only --quiet
else
  mkdir -p "$(dirname "$CW_REPO")"
  git clone --quiet https://github.com/mikeengleai/claude-workspaces.git "$CW_REPO"
fi
mkdir -p "$HOME/.local/share/claude-workspaces"
(cd "$CW_REPO" && HARNESS_INSTALL_DIR="$HOME/.local/share/claude-workspaces" sh deploy/install.sh)
echo "  Installed claude-workspaces → ~/bin/cw"

# 3. Install cookie import tool
cp "$REPO_DIR/bin/import-cookies" "$BIN_DIR/import-cookies"
chmod +x "$BIN_DIR/import-cookies"
echo "  Installed import-cookies → ~/bin/"

# 4. Create directories
mkdir -p "$HOME/workspaces"
mkdir -p "$HOME/.agent-browser/profiles"
echo "  Created ~/workspaces/ and ~/.agent-browser/profiles/"

echo
echo "Done. Run 'source ~/.bashrc' then 'cw' to start."

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

# 2. Install claude-workspaces (cw)
cp "$REPO_DIR/bin/claude-workspaces" "$BIN_DIR/claude-workspaces"
chmod +x "$BIN_DIR/claude-workspaces"
ln -sf "$BIN_DIR/claude-workspaces" "$BIN_DIR/cw"
echo "  Installed claude-workspaces → ~/bin/cw"

# 3. Install compaction prompt
cp "$REPO_DIR/bin/compaction-prompt.md" "$BIN_DIR/compaction-prompt.md"
echo "  Installed compaction-prompt.md → ~/bin/"

# 4. Install cookie import tool
cp "$REPO_DIR/bin/import-cookies" "$BIN_DIR/import-cookies"
chmod +x "$BIN_DIR/import-cookies"
echo "  Installed import-cookies → ~/bin/"

# 5. Create directories
mkdir -p "$HOME/workspaces"
mkdir -p "$HOME/.agent-browser/profiles"
echo "  Created ~/workspaces/ and ~/.agent-browser/profiles/"

echo
echo "Done. Run 'source ~/.bashrc' then 'cw' to start."

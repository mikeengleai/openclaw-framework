#!/usr/bin/env bash
# install.sh — Set up OpenClaw Framework tools from this repo.
# Run after cloning: ~/openclaw-framework/install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/bin"
WORKSPACES_DIR="$HOME/workspaces"

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

# 4. Create workspaces directory
mkdir -p "$WORKSPACES_DIR"
echo "  Created ~/workspaces/"

# 5. Verify
echo
if command -v cw &>/dev/null; then
  echo "Done. Run 'cw' to start the workspace manager."
else
  echo "Done. Run 'source ~/.bashrc' (or restart your shell), then 'cw'."
fi

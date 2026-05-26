#!/usr/bin/env bash
# bootstrap.sh — Minimum bootstrap to get Claude Code running.
# Claude Code handles all remaining setup from the README instructions.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash

set -euo pipefail

echo "=== OpenClaw Bootstrap ==="
echo

# 1. Install Node.js 20 (required for Claude Code)
if command -v node &>/dev/null && [[ "$(node -v)" == v2* ]]; then
  echo "Node.js $(node -v) already installed."
else
  echo "Installing Node.js 20..."
  sudo apt update -qq
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt install -y -qq nodejs
fi

# 2. Install git (Claude Code needs it to clone the framework repo)
if ! command -v git &>/dev/null; then
  echo "Installing git..."
  sudo apt install -y -qq git
fi

# 3. Install Claude Code
echo "Installing Claude Code..."
sudo npm install -g @anthropic-ai/claude-code

echo
echo "=== Bootstrap complete ==="
echo
echo "Next steps:"
echo
echo "  1. claude login"
echo "  2. claude --dangerously-skip-permissions"
echo "  3. Paste this prompt:"
echo
cat <<'PROMPT'
     Follow the setup instructions at https://github.com/mikeengleai/openclaw-framework
     to configure this server. Clone the repo, run the install script, install OpenClaw,
     install all dependencies, and verify everything works.
PROMPT
echo

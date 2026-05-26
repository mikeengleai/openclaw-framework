#!/usr/bin/env bash
# bootstrap.sh — Get Claude Code running on a fresh Ubuntu box.
# After this, Claude Code handles all remaining setup.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash

set -euo pipefail

echo "=== OpenClaw Bootstrap ==="
echo

# 1. System update
echo "Updating system packages..."
sudo apt update -qq && sudo apt upgrade -y -qq

# 2. Install Node.js 20 (required for Claude Code and agent-browser)
if command -v node &>/dev/null && [[ "$(node -v)" == v2* ]]; then
  echo "Node.js $(node -v) already installed."
else
  echo "Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt install -y -qq nodejs
fi

# 3. Install essential system packages
echo "Installing system dependencies..."
sudo apt install -y -qq git python3 python3-pip python3-venv sqlite3 tmux curl jq

# 4. Install Claude Code
echo "Installing Claude Code..."
sudo npm install -g @anthropic-ai/claude-code

# 5. Install agent-browser (headless Chrome with persistent profiles)
echo "Installing agent-browser..."
sudo npm install -g agent-browser

# 6. Create profile directory for agent-browser
mkdir -p ~/.agent-browser/profiles

echo
echo "=== Bootstrap complete ==="
echo
echo "Next steps:"
echo "  1. Run: claude login"
echo "  2. Authenticate in your browser"
echo "  3. Run: claude"
echo "  4. Paste this prompt into Claude Code:"
echo
echo '     Install the OpenClaw framework from https://github.com/mikeengleai/openclaw-framework.git'
echo '     Clone it to ~/openclaw-framework, run the install.sh script, then verify everything'
echo '     works by running "cw". Also verify agent-browser is installed: "agent-browser --version".'
echo

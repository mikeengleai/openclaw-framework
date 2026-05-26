#!/usr/bin/env bash
# post-onboard.sh — Run after openclaw onboard completes.
# Installs remaining dependencies, tools, and plugins.
#
# Run as the openclaw user (not root):
#   curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/post-onboard.sh | bash

set -euo pipefail

echo "=== OpenClaw Post-Onboard Setup ==="
echo

# Must NOT run as root
if [[ $EUID -eq 0 ]]; then
  echo "Error: run this as the openclaw user, not root."
  exit 1
fi

# 1. System dependencies
echo "[1/7] Installing system dependencies..."
sudo apt update -qq && sudo apt upgrade -y -qq
sudo apt install -y -qq python3 python3-pip python3-venv sqlite3 tmux curl jq unzip
pip3 install cryptography 2>/dev/null || pip3 install --break-system-packages cryptography 2>/dev/null || true
echo "  Done."

# 2. agent-browser + Chrome
echo "[2/7] Installing agent-browser and Chrome..."
if command -v agent-browser &>/dev/null; then
  echo "  agent-browser already installed: $(agent-browser --version)"
else
  sudo npm install -g agent-browser
fi
agent-browser install --with-deps
mkdir -p ~/.agent-browser/profiles
echo "  Done."

# 3. Tailscale
echo "[3/7] Installing Tailscale..."
if command -v tailscale &>/dev/null; then
  echo "  Tailscale already installed."
else
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! sudo tailscale status &>/dev/null 2>&1; then
  echo "  Run 'sudo tailscale up' after this script to authenticate."
else
  echo "  Tailscale already connected."
fi

# 4. Clone and install framework
echo "[4/7] Installing OpenClaw Framework tools..."
if [[ -d "$HOME/openclaw-framework" ]]; then
  echo "  Repo already cloned, pulling latest..."
  cd "$HOME/openclaw-framework" && git pull --ff-only && cd -
else
  git clone https://github.com/mikeengleai/openclaw-framework.git "$HOME/openclaw-framework"
fi
"$HOME/openclaw-framework/install.sh"
echo "  Done."

# 5. Superpowers plugin for Claude Code
echo "[5/7] Installing Superpowers plugin..."
if command -v claude &>/dev/null; then
  claude plugins add https://github.com/obra/superpowers 2>/dev/null || true
  echo "  Done."
else
  echo "  Skipped — Claude Code not found."
fi

# 6. Create workspaces directory
echo "[6/7] Creating workspaces directory..."
mkdir -p "$HOME/workspaces"
echo "  Done."

# 7. Verify
echo "[7/7] Verifying installation..."
echo
PASS=0
FAIL=0

check() {
  if eval "$2" &>/dev/null; then
    echo "  OK  $1: $(eval "$3" 2>/dev/null || echo "installed")"
    ((PASS++))
  else
    echo "  FAIL $1"
    ((FAIL++))
  fi
}

check "Node.js"        "command -v node"          "node -v"
check "Python3"        "command -v python3"       "python3 --version"
check "SQLite"         "command -v sqlite3"       "sqlite3 --version | head -1"
check "tmux"           "command -v tmux"          "tmux -V"
check "OpenClaw"       "command -v openclaw"      "openclaw --version 2>/dev/null | head -1"
check "agent-browser"  "command -v agent-browser" "agent-browser --version"
check "Claude Code"    "command -v claude"        "claude --version 2>/dev/null | head -1"

echo
echo "  $PASS passed, $FAIL failed"
echo

if [[ $FAIL -gt 0 ]]; then
  echo "Some checks failed. Review the output above and fix before continuing."
  exit 1
fi

echo "=== Post-onboard setup complete ==="
echo
echo "Next steps:"
echo
echo "  1. If Tailscale needs auth:  sudo tailscale up"
echo "  2. Start the gateway:        nohup openclaw gateway --foreground &>/dev/null &"
echo "  3. Reload PATH and start:    source ~/.bashrc && cw"
echo

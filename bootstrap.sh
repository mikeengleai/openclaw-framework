#!/usr/bin/env bash
# bootstrap.sh — Minimum bootstrap to get Claude Code running.
# Claude Code handles all remaining setup from the README instructions.
#
# Run as root on a fresh Ubuntu server:
#   curl -fsSL https://raw.githubusercontent.com/mikeengleai/openclaw-framework/main/bootstrap.sh | bash

set -euo pipefail

echo "=== OpenClaw Bootstrap ==="
echo

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: run this script as root (or with sudo)."
  exit 1
fi

# 1. Install Node.js 20
if command -v node &>/dev/null && [[ "$(node -v)" == v2* ]]; then
  echo "Node.js $(node -v) already installed."
else
  echo "Installing Node.js 20..."
  apt update -qq
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y -qq nodejs
fi

# 2. Install git
if ! command -v git &>/dev/null; then
  echo "Installing git..."
  apt install -y -qq git
fi

# 3. Install Claude Code
echo "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# 4. Install OpenClaw
echo "Installing OpenClaw..."
npm install -g openclaw

# Verify both are on PATH
echo "  Claude Code: $(claude --version 2>/dev/null | head -1 || echo 'installed')"
echo "  OpenClaw:    $(openclaw --version 2>/dev/null | head -1 || echo 'installed')"

# 5. Create the openclaw user (if it doesn't exist)
if id openclaw &>/dev/null; then
  echo "User 'openclaw' already exists."
else
  echo "Creating user 'openclaw'..."
  adduser --disabled-password --gecos "OpenClaw" openclaw
  usermod -aG sudo openclaw
  # Allow passwordless sudo for the session (user can tighten later)
  echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw
  echo "  Created user 'openclaw' with sudo access."
fi

echo
echo "=== Bootstrap complete ==="
echo
echo "  Open the setup guide in your browser and follow the steps there:"
echo
echo "  https://github.com/mikeengleai/openclaw-framework#quick-start"
echo
echo "  You are done with Phase 1. Continue from Phase 2."
echo
echo "  First command: su - openclaw"
echo

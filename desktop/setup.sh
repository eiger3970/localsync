#!/usr/bin/env bash
# LocalSync desktop setup - zero-prerequisite version of setup.yml.
#
# Run: bash desktop/setup.sh
# Skip auto-discovery: bash desktop/setup.sh --skip-discovery
#
# 2026-09-01: real gap found - setup.yml's own "one command" story
# secretly assumed Ansible was already installed, which it isn't by
# default on Debian-based Linux OR macOS. Asking a first-time normie
# user to also figure out installing Ansible before this app's own
# setup can even start defeats the "minimal interaction" goal outright.
# This does the exact same idempotent steps (git, SSH, the bare repo,
# avahi/Bonjour discovery) using nothing but bash + sudo + the OS's own
# package manager - already present on every target machine, no
# separate tool to install first. setup.yml is left in place for anyone
# who already has Ansible and prefers it; this is the one recommended
# by docs/desktop-setup.md now.
#
# SCOPE: Debian-based Linux (Linux Mint, Ubuntu, Raspberry Pi OS) and
# macOS. Windows is a real, separate problem (no native SSH-by-default,
# no apt/brew equivalent) - deliberately out of scope, not an oversight.
#
# Idempotent - safe to re-run. Nothing here deletes or overwrites
# existing data; the bare repo step only runs if the target path
# doesn't already exist.

set -uo pipefail

SKIP_DISCOVERY=false
for arg in "$@"; do
  case "$arg" in
    --skip-discovery) SKIP_DISCOVERY=true ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BARE_REPO_DIR="$HOME/Documents/Git/LocalSync"
BARE_REPO_PATH="$BARE_REPO_DIR/vault.git"
SSH_PORT=22

log() { echo "==> $*"; }

case "$(uname -s)" in
  Linux)
    if [[ -f /etc/debian_version ]]; then OS=debian; else OS=other-linux; fi
    ;;
  Darwin) OS=macos ;;
  *) OS=other ;;
esac

if [[ "$OS" != "debian" && "$OS" != "macos" ]]; then
  echo "This script covers Debian-based Linux and macOS only." >&2
  echo "Your desktop's own package manager isn't one of those - follow" >&2
  echo "docs/desktop-setup.md's manual steps instead." >&2
  exit 1
fi

# ── Git ──────────────────────────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
  log "git already installed - skipping"
elif [[ "$OS" == debian ]]; then
  log "Installing git"
  sudo apt-get update && sudo apt-get install -y git
else
  echo "git isn't detected. On macOS, git installs alongside the Xcode" >&2
  echo "Command Line Tools, which need an interactive prompt this script" >&2
  echo "can't complete automatically - run 'git --version' once by hand" >&2
  echo "to trigger the install prompt, then re-run this script." >&2
fi

# ── SSH access ───────────────────────────────────────────────────────────
if [[ "$OS" == debian ]]; then
  if systemctl is-active --quiet ssh 2>/dev/null; then
    log "SSH already running - skipping"
  else
    log "Installing and enabling openssh-server"
    sudo apt-get install -y openssh-server
    sudo systemctl enable --now ssh
  fi
else
  log "Enabling Remote Login (macOS)"
  sudo systemsetup -setremotelogin on
fi

# ── Git bare repository ──────────────────────────────────────────────────
if [[ -d "$BARE_REPO_PATH" ]]; then
  log "Bare repo already exists at $BARE_REPO_PATH - skipping"
else
  log "Creating the bare repo at $BARE_REPO_PATH"
  mkdir -p "$BARE_REPO_DIR"
  git init --bare "$BARE_REPO_PATH"
fi
echo
echo "Git bare repo path (enter this into LocalSync's Settings):"
echo "  $BARE_REPO_PATH"
echo

# ── Auto-discovery (optional) ────────────────────────────────────────────
if [[ "$SKIP_DISCOVERY" == true ]]; then
  log "Skipping auto-discovery setup (--skip-discovery)"
elif [[ "$OS" == debian ]]; then
  if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    log "avahi-daemon already running"
  else
    log "Installing and enabling avahi-daemon"
    sudo apt-get install -y avahi-daemon
    sudo systemctl enable --now avahi-daemon
  fi
  log "Installing the LocalSync avahi service file"
  sudo cp "$SCRIPT_DIR/localsync.service" /etc/avahi/services/localsync.service
  sudo systemctl restart avahi-daemon
else
  log "Advertising via Bonjour (persistent LaunchDaemon)"
  PLIST=/Library/LaunchDaemons/space.kworld.localsync.discovery.plist
  sudo tee "$PLIST" >/dev/null <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>space.kworld.localsync.discovery</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/dns-sd</string>
    <string>-R</string>
    <string>LocalSync</string>
    <string>_localsync._tcp</string>
    <string>local</string>
    <string>$SSH_PORT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
PLIST_EOF
  sudo launchctl unload "$PLIST" 2>/dev/null || true
  sudo launchctl load "$PLIST"
fi

echo
log "Done."

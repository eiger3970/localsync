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

# 2026-09-02: real feedback, live - "I see a lot of notepad text,
# starting with git already installed. User needs to see the answer at
# top, not how the sausage is made." Fair - the step-by-step
# install/skip log used to be the FIRST thing in the file, with the
# actual answer (which path to use) buried at the bottom. Everything
# that does real system work is now one function, its output captured
# instead of printed live, so it can be placed AFTER the answer instead
# of before it. sudo's own password prompt still works normally here -
# it talks to the controlling terminal directly, not through stdout, so
# capturing stdout doesn't hide or break it.
run_technical_setup() {
  # ── Git ────────────────────────────────────────────────────────────────
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

  # ── SSH access ─────────────────────────────────────────────────────────
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

  # ── Git bare repository ────────────────────────────────────────────────
  if [[ -d "$BARE_REPO_PATH" ]]; then
    log "Bare repo already exists at $BARE_REPO_PATH - skipping"
  else
    log "Creating the bare repo at $BARE_REPO_PATH"
    mkdir -p "$BARE_REPO_DIR"
    git init --bare "$BARE_REPO_PATH"
  fi

  # ── Auto-discovery (optional) ─────────────────────────────────────────
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
    # 2026-09-01: real bug, caught testing the self-verifying Mac
    # wrapper - when this script runs from a curl download or a temp
    # file (not a checkout of this repo), $SCRIPT_DIR/localsync.service
    # doesn't exist alongside it, so the cp below failed silently.
    # Written inline instead - matches the macOS branch's own heredoc
    # pattern below - so this works identically however the script was
    # actually obtained.
    log "Installing the LocalSync avahi service file"
    sudo tee /etc/avahi/services/localsync.service >/dev/null <<'SERVICE_EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">LocalSync on %h</name>
  <service>
    <type>_localsync._tcp</type>
    <port>22</port>
  </service>
</service-group>
SERVICE_EOF
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
}

TECH_LOG=$(run_technical_setup 2>&1)

# ── The answer, first ────────────────────────────────────────────────────
# 2026-09-03: real feedback, live - "these commands are impossible to
# read and type into desktop terminal, too long. Can these commands be
# installed on the website deb file?" The app's own "Manual setup"
# dialogs (Settings -> each field's (i) button) walk a user through
# typing a long one-liner into a terminal by hand for the IP address and
# vault path fields too - the same problem the 2026-09-02 fix below
# already solved for the sync-folder field alone. Folded the other two
# in here as well, so every Settings field this desktop can answer gets
# answered by running this ONE script (.deb, .command, or by hand) -
# nothing left to relay from the phone at all except pairing itself.

echo "Desktop username (enter this into LocalSync's Settings):"
# 2026-09-04: real bug, caught by actually installing the .deb - this
# printed "root" instead of the real desktop user. whoami() reflects
# the actual process UID, which the .deb's postinst always runs as
# root regardless of the HOME override it already applies for path-
# building below - HOME isn't what whoami reads. postinst resolves the
# real invoking user via SUDO_USER/PKEXEC_UID/logname and exports it as
# LOCALSYNC_USER before calling this script; the .command and manual
# curl|bash paths never set that, so whoami stays correct there (a
# real logged-in user running this directly, not via a root postinst).
echo "  ${LOCALSYNC_USER:-$(whoami)}"
echo

# 2026-09-03: matches the app's own IP dialog exactly (same eth1/usb0
# filter, same reasoning: this Pi alone has 6 unrelated Docker bridge
# interfaces plus loopback that raw `ip addr`/`ifconfig` would otherwise
# surface). Linux-only for now, same scope the app's dialog already has
# - it has never attempted macOS interface names (different naming
# entirely for USB tethering/Personal Hotspot), so this doesn't invent
# unverified behavior for a platform nobody's confirmed it against yet.
echo "Desktop IP address (enter this into LocalSync's Settings) - only"
echo "needed if the phone's auto-discovery can't find this desktop on"
echo "its own, and can change if you switch between USB cable and Wi-Fi"
echo "Hotspot:"
if [[ "$OS" == debian ]]; then
  IP_RESULT=$(ip -4 addr show 2>/dev/null | awk '$0 ~ /^[0-9]+: (eth1|usb0):/{f=1;next} /^[0-9]+:/{f=0} f && /inet /{split($2,a,"/"); print a[1]}')
  if [[ -z "$IP_RESULT" ]]; then
    echo "  No eth1 or usb0 connection found - connect the phone's USB"
    echo "  cable or turn on its Wi-Fi Hotspot, then re-run this script"
  else
    echo "  $IP_RESULT"
  fi
else
  echo "  Not auto-detected on macOS yet - use LocalSync's Settings ->"
  echo "  2. IP ADDRESS - DESKTOP -> (i) -> Manual setup on your phone"
fi
echo

echo "Git bare repo path (enter this into LocalSync's Settings):"
echo "  $BARE_REPO_PATH"
echo

# ── Existing LocalSync folders ───────────────────────────────────────────
# 2026-09-02: real feedback, live - "make it optimised so I just
# download the website deb file, rather than type out that long
# command showing on the phone." This is the exact same logic the
# app's own "Manual setup" dialog (Settings -> 2. DESKTOP SYNC FOLDER
# -> i) walks a user through typing into a terminal by hand - folded
# in here instead, so it runs automatically as part of the one
# desktop setup step (.deb, .command, or this script directly), no
# separate command to relay from the phone at all. Only matters for
# reconnecting to a PREVIOUS pairing's real data (reinstalled the app,
# switched phones, or - like right now - a desktop with old test
# pairings on it already); a genuinely first-time setup can ignore
# this and use the path printed above.
# 2026-09-02: real feedback, live - "that will give me and users a
# heart attack. Can this text file be beautified, to see the most
# pertinent information." Fair - dumping every .git folder on the
# machine (most of them unrelated dev projects) read as an alarming
# wall of text, not something reassuring. Now filters to only genuine
# LocalSync candidates (a real sync's message always starts with
# "Desktop sync", "Desktop conflicting edit", or "Initial sync from
# phone" - the app's own fixed commit-message conventions) or empty
# repos, and just counts everything else instead of listing it.
echo "Desktop sync folders:"
echo
FOUND_MATCH=false
UNRELATED_COUNT=0
while IFS= read -r -d '' d; do
  msg=$(git --git-dir="$d" log -1 --format='%s' 2>/dev/null)
  when=$(git --git-dir="$d" log -1 --format='%ad' --date=short 2>/dev/null)
  if [[ -z "$msg" ]]; then
    echo "  $d"
    echo "    empty - safe to use"
    FOUND_MATCH=true
  elif [[ "$msg" == "Desktop sync"* || "$msg" == "Desktop conflicting edit"* || "$msg" == "Initial sync from phone"* ]]; then
    echo "  $d"
    echo "    last used $when - $msg"
    FOUND_MATCH=true
  else
    UNRELATED_COUNT=$((UNRELATED_COUNT + 1))
  fi
done < <(find "$HOME/Documents/Git" -maxdepth 3 -name '*.git' -type d -print0 2>/dev/null)

if [[ "$UNRELATED_COUNT" -eq 1 ]]; then
  echo
  echo "  (1 other folder here looks like an unrelated project, not"
  echo "  LocalSync data, so it's skipped above.)"
elif [[ "$UNRELATED_COUNT" -gt 1 ]]; then
  echo
  echo "  ($UNRELATED_COUNT other folders here look like unrelated"
  echo "  projects, not LocalSync data, so they're skipped above.)"
fi

echo
if [[ "$FOUND_MATCH" == true ]]; then
  echo "If one of the folders above is yours, type its path into"
  echo "LocalSync's Settings -> 2. DESKTOP SYNC FOLDER field on your"
  echo "phone. Not sure? This path is a safe, empty default:"
else
  echo "No previous LocalSync folders found here - normal for a first"
  echo "time setup. Use this path in LocalSync's Settings on your phone:"
fi
echo "  $BARE_REPO_PATH"

# ── Desktop vault path ────────────────────────────────────────────────────
# 2026-09-03: same scoring the app's own "Desktop vault path" dialog
# uses (60% weight on how recently a candidate was edited, 40% on note
# count, both relative to whichever candidate wins each measure) - one
# plain-language answer instead of making someone compare raw numbers
# across every folder Obsidian has ever opened.
echo
echo "Desktop vault path (enter this into LocalSync's Settings, only if"
echo "you're recovering an existing vault - leave blank on your phone"
echo "for a fresh, empty folder instead):"
VAULT_RESULT=$(find "$HOME/Documents" -maxdepth 3 -iname "*.obsidian" -type d 2>/dev/null | sed 's#/.obsidian$##' | while read -r v; do
  n=$(find "$v" -iname "*.md" 2>/dev/null | wc -l)
  e=$(find "$v" -iname "*.md" -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
  e=${e%.*}
  echo "$v|$n|${e:-0}"
done | awk -F'|' '{p[NR]=$1;n[NR]=$2;e[NR]=$3; if($2+0>maxn)maxn=$2+0; if($3+0>maxe)maxe=$3+0} END{for(i=1;i<=NR;i++){ns=(maxn>0)?n[i]/maxn:0; age=(maxe-e[i])/86400; rs=(age<=0)?1:1/(1+age/14); sc=int(100*(0.4*ns+0.6*rs)); if(sc>100)sc=100; print p[i]"|"sc"|"n[i]"|"e[i]}}' | sort -t'|' -k2 -rn)
BEST_VAULT_PATH=""
if [[ -z "$VAULT_RESULT" ]]; then
  echo "  No Obsidian vaults found under $HOME/Documents - normal for a"
  echo "  first-time setup, leave this field blank on your phone"
else
  BEST_VAULT_PATH=$(echo "$VAULT_RESULT" | head -1 | cut -d'|' -f1)
  VAULT_COUNT=$(echo "$VAULT_RESULT" | wc -l)
  echo "$VAULT_RESULT" | head -1 | while IFS='|' read -r path score notes epoch; do
    d=$(date -d "@$epoch" +%Y-%m-%d 2>/dev/null || echo unknown)
    echo "  $path"
    echo "    ~${score}% likely your real vault ($notes notes, last edited $d)"
  done
  if [[ "$VAULT_COUNT" -gt 1 ]]; then
    echo
    echo "  ($((VAULT_COUNT - 1)) other, lower-scored candidate(s) also"
    echo "  found - the path above is the best match)"
  fi
fi

# ── Combined setup QR code ────────────────────────────────────────────────
# 2026-09-04: real gap, live - "this is where the desktop file that
# shows all the setup autom wtih qr scanner et al should run, but the
# user needs to be informed, preferably visually." The app's own
# Settings screen already has a QR scan button (added earlier today)
# but nothing on the desktop side ever generated a QR to scan - this
# closes that loop. One QR encodes all four Settings fields at once
# (magic first line so the app can tell a real LocalSync QR from an
# unrelated one someone might scan by mistake) - one scan instead of
# retyping four values by hand, the actual "critical data, get it
# wrong and risk your data" problem flagged directly. Runs in the same
# terminal window already open for every distribution path (.deb,
# .command, curl|bash) - a real terminal is always monospace, so no
# separate HTML/image file is needed the way a font-uncertain plain
# text viewer would require. Skips gracefully, no auto-install, if
# qrencode isn't present - the plain-text values above already cover
# that case, this is a real enhancement, not a hard requirement.
if command -v qrencode >/dev/null 2>&1; then
  echo
  echo "=================================================================="
  echo "SCAN THIS ON YOUR PHONE - fills in all 4 Settings fields at once"
  echo "(open LocalSync's Settings, tap the QR icon next to any field)"
  echo "=================================================================="
  printf 'localsync-setup-v1\n%s\n%s\n%s\n%s\n' \
    "${LOCALSYNC_USER:-$(whoami)}" "${IP_RESULT:-}" "$BARE_REPO_PATH" "$BEST_VAULT_PATH" \
    | qrencode -t ANSIUTF8
  echo
else
  echo
  echo "(Install qrencode for a scannable QR code here instead of typing"
  echo "the above by hand - e.g. 'sudo apt install qrencode' or 'brew"
  echo "install qrencode', then re-run this file.)"
fi

# ── Setup details, last - not the headline, just for reference ──────────
echo
echo "Setup details:"
echo "$TECH_LOG" | sed 's/^/  /'

echo
log "Done."

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

# 2026-09-04: real feedback, live - "I need to see the output in a
# possible same format as the app, so that would be a nice green
# terminal colour and style perhaps?" Matches the app's own accent
# green (the HTML popup below already uses #6fff8f). No `[ -t 1 ]`
# gate - the .deb's postinst always pipes this through `tee`, which
# makes stdout a pipe, not a tty, so a tty check would silently kill
# the color for every .deb install, the exact case this request is
# about. postinst strips these codes back out before saving its own
# copy to a plain text file, so this doesn't reopen the escape-code-
# in-a-text-file bug found earlier the same day.
GREEN=$'\033[1;32m'
DIM=$'\033[2;32m'
RESET=$'\033[0m'

# 2026-09-04: real feedback, live - "is it possible to have the logo at
# the top, so users know it's 100% from LocalSync?" The QR popup is a
# standalone HTML file with no network access assumed (opened straight
# from disk) and no copy of the website's own asset files sitting next
# to it, so the real logo (same file kworld.space/localsync itself
# uses: public/assets/localsync/logo_word_with_circle.svg) is baked in
# here as base64, the same way the QR image itself already gets
# embedded as base64 PNG a few lines down - not a new pattern, just the
# same one applied to a second image.
LOCALSYNC_LOGO_B64="PHN2ZyB3aWR0aD0iODcuOSIgaGVpZ2h0PSIxMC4yIiB2aWV3Qm94PSIwIDAgODcuOSAxMC4yIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8ZGVmcz4KPGxpbmVhckdyYWRpZW50IGlkPSJnR3JlZW4iIHgxPSIwJSIgeTE9IjAlIiB4Mj0iMTAwJSIgeTI9IjEwMCUiPgogIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiNiYWZmYjAiLz4KICA8c3RvcCBvZmZzZXQ9IjU1JSIgc3RvcC1jb2xvcj0iIzAwRkY0MSIvPgogIDxzdG9wIG9mZnNldD0iMTAwJSIgc3RvcC1jb2xvcj0iIzAwYjgyZiIvPgo8L2xpbmVhckdyYWRpZW50Pgo8cmFkaWFsR3JhZGllbnQgaWQ9ImdHbG93IiBjeD0iNTAlIiBjeT0iNTAlIiByPSI1MCUiPgogIDxzdG9wIG9mZnNldD0iMCUiIHN0b3AtY29sb3I9IiMwMEZGNDEiIHN0b3Atb3BhY2l0eT0iMC40NSIvPgogIDxzdG9wIG9mZnNldD0iMTAwJSIgc3RvcC1jb2xvcj0iIzAwRkY0MSIgc3RvcC1vcGFjaXR5PSIwIi8+CjwvcmFkaWFsR3JhZGllbnQ+CjxmaWx0ZXIgaWQ9ImdCbHVyIiB4PSItODAlIiB5PSItODAlIiB3aWR0aD0iMjYwJSIgaGVpZ2h0PSIyNjAlIj4KICA8ZmVHYXVzc2lhbkJsdXIgc3RkRGV2aWF0aW9uPSI4Ii8+CjwvZmlsdGVyPgo8L2RlZnM+Cjx0ZXh0IHg9IjAuMDAiIHk9IjEwLjI1IiBmb250LWZhbWlseT0iQ291cmllciBOZXcsIERlamFWdSBTYW5zIE1vbm8sIG1vbm9zcGFjZSIgZm9udC13ZWlnaHQ9IjYwMCIgZm9udC1zaXplPSIxNCIgZmlsbD0iIzAwRkY0MSI+TDwvdGV4dD4KPGcgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTQuMTQsNS4xMikgc2NhbGUoMC4xMTE0MSkiPgogICAgPGNpcmNsZSBjeD0iMCIgY3k9IjAiIHI9IjUyIiBmaWxsPSJ1cmwoI2dHbG93KSIgZmlsdGVyPSJ1cmwoI2dCbHVyKSIvPgogICAgPGNpcmNsZSBjeD0iMCIgY3k9IjAiIHI9IjQ0IiBmaWxsPSJub25lIiBzdHJva2U9InVybCgjZ0dyZWVuKSIgc3Ryb2tlLXdpZHRoPSI0Ii8+CiAgICA8ZyBmaWxsPSJub25lIiBzdHJva2U9InVybCgjZ0dyZWVuKSIgc3Ryb2tlLXdpZHRoPSI4IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPgogICAgICA8cG9seWxpbmUgcG9pbnRzPSItMTksLTE5IC01LDAgLTE5LDE5IiBvcGFjaXR5PSIwLjM1Ii8+CiAgICAgIDxwb2x5bGluZSBwb2ludHM9Ii02LC0xOSA4LDAgLTYsMTkiIG9wYWNpdHk9IjAuNjUiLz4KICAgICAgPHBvbHlsaW5lIHBvaW50cz0iNywtMTkgMjEsMCA3LDE5IiBvcGFjaXR5PSIxLjAiLz4KICAgIDwvZz4KICA8L2c+Cjx0ZXh0IHg9IjE5Ljg2IiB5PSIxMC4yNSIgZm9udC1mYW1pbHk9IkNvdXJpZXIgTmV3LCBEZWphVnUgU2FucyBNb25vLCBtb25vc3BhY2UiIGZvbnQtd2VpZ2h0PSI2MDAiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMwMEZGNDEiPkM8L3RleHQ+Cjx0ZXh0IHg9IjI5Ljc5IiB5PSIxMC4yNSIgZm9udC1mYW1pbHk9IkNvdXJpZXIgTmV3LCBEZWphVnUgU2FucyBNb25vLCBtb25vc3BhY2UiIGZvbnQtd2VpZ2h0PSI2MDAiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMwMEZGNDEiPkE8L3RleHQ+Cjx0ZXh0IHg9IjM5LjcyIiB5PSIxMC4yNSIgZm9udC1mYW1pbHk9IkNvdXJpZXIgTmV3LCBEZWphVnUgU2FucyBNb25vLCBtb25vc3BhY2UiIGZvbnQtd2VpZ2h0PSI2MDAiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMwMEZGNDEiPkw8L3RleHQ+Cjx0ZXh0IHg9IjQ5LjY1IiB5PSIxMC4yNSIgZm9udC1mYW1pbHk9IkNvdXJpZXIgTmV3LCBEZWphVnUgU2FucyBNb25vLCBtb25vc3BhY2UiIGZvbnQtd2VpZ2h0PSI2MDAiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMwMEZGNDEiPlM8L3RleHQ+Cjx0ZXh0IHg9IjU5LjU4IiB5PSIxMC4yNSIgZm9udC1mYW1pbHk9IkNvdXJpZXIgTmV3LCBEZWphVnUgU2FucyBNb25vLCBtb25vc3BhY2UiIGZvbnQtd2VpZ2h0PSI2MDAiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMwMEZGNDEiPlk8L3RleHQ+Cjx0ZXh0IHg9IjY5LjUxIiB5PSIxMC4yNSIgZm9udC1mYW1pbHk9IkNvdXJpZXIgTmV3LCBEZWphVnUgU2FucyBNb25vLCBtb25vc3BhY2UiIGZvbnQtd2VpZ2h0PSI2MDAiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMwMEZGNDEiPk48L3RleHQ+Cjx0ZXh0IHg9Ijc5LjQ0IiB5PSIxMC4yNSIgZm9udC1mYW1pbHk9IkNvdXJpZXIgTmV3LCBEZWphVnUgU2FucyBNb25vLCBtb25vc3BhY2UiIGZvbnQtd2VpZ2h0PSI2MDAiIGZvbnQtc2l6ZT0iMTQiIGZpbGw9IiMwMEZGNDEiPkM8L3RleHQ+Cjwvc3ZnPgo="

log() { echo "${DIM}==>${RESET} $*"; }

# 2026-09-04: real bug, caught by the user's own real terminal paste -
# the .deb install printed "(Also opened in your browser...)" but no
# window ever appeared. Root cause #1: the .deb's postinst runs this
# whole script as root (HOME is overridden to the real user's, but the
# process itself is still root), so a plain `xdg-open` here tries to
# open a browser AS root - which has no DISPLAY of its own and, even
# where sudo happens to leak one through, is refused by the real
# user's X/Wayland session anyway (root isn't authorized against their
# session cookie). Direct runs (this script by hand, the .command
# wrapper, curl|bash) never hit this - LOCALSYNC_USER is only set by
# postinst, and EUID is the real user's own there already. Fixed by
# pulling DISPLAY/WAYLAND_DISPLAY straight from one of the real user's
# own already-running processes (the actual live answer, not a guessed
# ":0"), then running the browser AS them via sudo -u.
#
# 2026-09-04 follow-up - real bug #2, found by comparing process start
# times against the user's own repeated real tests: `xdg-open` WAS
# reaching the real user's already-running Firefox each time (a new
# tab's content process spawned right when the command ran) - it just
# opened as a background tab, not a focused window, so it was never
# actually visible. Wayland compositors (this desktop runs labwc)
# deliberately refuse to let a background process raise or steal focus
# onto an EXISTING window - the fix above got the display connection
# right but still hit this second, unrelated restriction. Asking
# Firefox itself for a brand new top-level window (rather than letting
# the generic xdg-open handler reuse the running instance's existing
# one) sidesteps it - compositors map and focus a genuinely NEW window
# far more readily than they'll let something bring an old one forward.
open_in_browser() {
  local file="$1"
  local -a browser_cmd=()
  if command -v firefox >/dev/null 2>&1; then
    browser_cmd=(firefox --new-window "$file")
  fi

  if [[ "$EUID" -ne 0 || -z "${LOCALSYNC_USER:-}" ]]; then
    if [[ "${#browser_cmd[@]}" -gt 0 ]]; then
      "${browser_cmd[@]}" >/dev/null 2>&1 &
      return 0
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$file" >/dev/null 2>&1 &
      return 0
    elif command -v open >/dev/null 2>&1; then
      open "$file" >/dev/null 2>&1 &
      return 0
    fi
    return 1
  fi

  local target_uid disp="" wdisp="" pid env_disp env_wdisp
  target_uid=$(id -u "$LOCALSYNC_USER" 2>/dev/null) || return 1
  for pid in $(pgrep -u "$target_uid" 2>/dev/null); do
    [[ -r "/proc/$pid/environ" ]] || continue
    env_disp=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p' | head -1)
    if [[ -n "$env_disp" ]]; then
      disp="$env_disp"
      env_wdisp=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p' | head -1)
      wdisp="$env_wdisp"
      break
    fi
  done
  [[ -z "$disp" ]] && disp=":0"
  # 2026-09-04 follow-up - real bug #3, live: "Firefox is already
  # running, but is not responding." Firefox's single-instance IPC (the
  # mechanism that turns "open this file" into a new window in the
  # ALREADY-running browser instead of a second, conflicting process)
  # goes over the user's D-Bus session bus on this desktop, not X
  # properties - DISPLAY/WAYLAND_DISPLAY/XAUTHORITY alone don't reach
  # it. Without XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS, the new
  # process can't find that bus, can't hand off to the running
  # instance, and collides with its profile lock file instead - exactly
  # this error. Both live at the standard, discoverable path for this
  # user's own runtime dir.
  local runtime_dir="/run/user/$target_uid"
  local dbus_addr="unix:path=$runtime_dir/bus"
  if [[ "${#browser_cmd[@]}" -gt 0 ]]; then
    sudo -u "$LOCALSYNC_USER" DISPLAY="$disp" WAYLAND_DISPLAY="$wdisp" XAUTHORITY="$HOME/.Xauthority" XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" "${browser_cmd[@]}" >/dev/null 2>&1 &
    return 0
  fi
  command -v xdg-open >/dev/null 2>&1 || return 1
  sudo -u "$LOCALSYNC_USER" DISPLAY="$disp" WAYLAND_DISPLAY="$wdisp" XAUTHORITY="$HOME/.Xauthority" XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" xdg-open "$file" >/dev/null 2>&1 &
}

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
echo "  ${GREEN}${LOCALSYNC_USER:-$(whoami)}${RESET}"
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
    echo "  ${GREEN}$IP_RESULT${RESET}"
  fi
else
  echo "  Not auto-detected on macOS yet - use LocalSync's Settings ->"
  echo "  2. IP ADDRESS - DESKTOP -> (i) -> Manual setup on your phone"
fi
echo

# ── Git bare repo path (an existing real setup wins over the default) ───
# 2026-09-02: real feedback, live - "make it optimised so I just
# download the website deb file, rather than type out that long
# command showing on the phone." This is the exact same logic the
# app's own "Manual setup" dialog (Settings -> 2. DESKTOP SYNC FOLDER
# -> i) walks a user through typing into a terminal by hand - folded
# in here instead, so it runs automatically as part of the one
# desktop setup step (.deb, .command, or this script directly), no
# separate command to relay from the phone at all.
# 2026-09-02: real feedback, live - "that will give me and users a
# heart attack. Can this text file be beautified, to see the most
# pertinent information." Fair - dumping every .git folder on the
# machine (most of them unrelated dev projects) read as an alarming
# wall of text, not something reassuring. Now filters to only genuine
# LocalSync candidates (a real sync's message always starts with
# "Desktop sync", "Desktop conflicting edit", or "Initial sync from
# phone" - the app's own fixed commit-message conventions) or empty
# repos, and just counts everything else instead of listing it.
# 2026-09-04: real gap, live - "why doesn't the QR scan output the
# correct path?" It didn't: this used to always print (and QR-encode) a
# fresh, empty default even when the scan just below found this SAME
# desktop's own real, previously-paired bare repo sitting right there
# with genuine sync history. The vault-path field a few lines down
# already auto-picks its own best real candidate instead of making
# someone read a list and correct it by hand - this now does the exact
# same thing here, since finding a real match and still not using it
# defeats the entire point of scanning in the first place.
echo "Desktop sync folders:"
echo
FOUND_MATCH=false
UNRELATED_COUNT=0
BEST_SYNC_FOLDER=""
BEST_SYNC_DATE=""
BEST_SYNC_EPOCH=""
while IFS= read -r -d '' d; do
  msg=$(git --git-dir="$d" log -1 --format='%s' 2>/dev/null)
  when=$(git --git-dir="$d" log -1 --format='%ad' --date=short 2>/dev/null)
  # 2026-09-04: real bug, caught comparing this against a second real
  # candidate touched the same day - %ad --date=short only has day
  # precision, so two candidates last used on the same calendar day
  # (routine once more than one thing syncs daily) tied here, and the
  # comparison below silently fell back to find's own traversal order
  # to break the tie instead of picking the ACTUALLY most recent one.
  # %at (a raw comparable epoch) is captured separately so the real
  # timestamp decides, while $when stays just for the human-readable
  # message.
  when_epoch=$(git --git-dir="$d" log -1 --format='%at' 2>/dev/null)
  if [[ -z "$msg" ]]; then
    echo "  $d"
    echo "    empty - safe to use"
    FOUND_MATCH=true
  elif [[ "$msg" == "Desktop sync"* || "$msg" == "Desktop conflicting edit"* || "$msg" == "Initial sync from phone"* ]]; then
    echo "  $d"
    echo "    last used $when - $msg"
    FOUND_MATCH=true
    if [[ -z "$BEST_SYNC_EPOCH" || "${when_epoch:-0}" -gt "$BEST_SYNC_EPOCH" ]]; then
      BEST_SYNC_EPOCH="$when_epoch"
      BEST_SYNC_DATE="$when"
      BEST_SYNC_FOLDER="$d"
    fi
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
if [[ -n "$BEST_SYNC_FOLDER" ]]; then
  BARE_REPO_PATH="$BEST_SYNC_FOLDER"
  echo "Found your existing setup above (last used $BEST_SYNC_DATE) -"
  echo "using it below and in the QR code automatically:"
elif [[ "$FOUND_MATCH" == true ]]; then
  echo "None of the folders above have real sync history yet. Not sure"
  echo "which to use? This path is a safe, empty default:"
else
  echo "No previous LocalSync folders found here - normal for a first"
  echo "time setup. Enter this path into LocalSync's Settings on your"
  echo "phone:"
fi
echo "  ${GREEN}$BARE_REPO_PATH${RESET}"

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
    echo "  ${GREEN}$path${RESET}"
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
# wrong and risk your data" problem flagged directly.
#
# 2026-09-04 follow-up - two real problems found testing this for real.
# (1) "still easy to lose amongst the terminal text output" - tried
# bold ANSI color on the banner text, but that's a half-measure at
# best. (2) far more serious, found while investigating (1): the .deb's
# postinst tees this whole terminal output (colored banner AND the
# ANSI-block QR itself) into a plain "LocalSync setup result.txt" file
# for anyone who installs via a GUI package manager with no visible
# terminal at all - opening that file in a text editor showed raw
# garbage (^[[1;32m escape codes, a QR rendered as scrambled block/
# escape-code soup) instead of anything readable. "The terminal is an
# unknown for noobs" - both problems point at the same real fix: stop
# treating the terminal as the primary place this QR lives at all.
# Reverted the ANSI banner coloring (a plain, ANSI-free banner is at
# least not ALSO broken in a saved text file), and instead generate a
# real standalone HTML file with the QR as an actual embedded PNG image
# - not ANSI blocks - auto-opened in the default browser via xdg-open/
# open. That's a genuine new window, no terminal literacy needed to
# read it, and it can never render as escape-code garbage the way a
# terminal-only QR can. The terminal's own plain-text values (and the
# ANSI QR, for anyone already comfortable there) stay as a fallback if
# opening a browser window fails for any reason.
if command -v qrencode >/dev/null 2>&1; then
  echo
  echo "${GREEN}=================================================================="
  echo "SCAN THIS ON YOUR PHONE - fills in all 4 Settings fields at once"
  echo "(open LocalSync's Settings, tap the QR icon next to any field)"
  echo "==================================================================${RESET}"
  QR_PAYLOAD=$(printf 'localsync-setup-v1\n%s\n%s\n%s\n%s\n' \
    "${LOCALSYNC_USER:-$(whoami)}" "${IP_RESULT:-}" "$BARE_REPO_PATH" "$BEST_VAULT_PATH")
  echo "$QR_PAYLOAD" | qrencode -t ANSIUTF8
  echo

  # 2026-09-04: real feedback, live - "the data needs to be vertical in
  # the format of the real app, so it's consistent and mirrors what the
  # user needs to match and see." Settings' own 4 fields stack
  # vertically, one below another - the two-column grid this used at
  # first broke that visual correspondence, making side-by-side
  # checking harder, not easier.
  QR_HTML="$(mktemp -t localsync-qr-XXXXXX).html"
  QR_PNG_B64=$(echo "$QR_PAYLOAD" | qrencode -o - -s 10 -m 2 | base64 -w0 2>/dev/null || echo "$QR_PAYLOAD" | qrencode -o - -s 10 -m 2 | base64)
  cat > "$QR_HTML" <<HTMLEOF
<!doctype html><html><head><meta charset="UTF-8">
<title>LocalSync setup</title>
<style>
body{margin:0;min-height:100vh;background:#0a0e0a;color:#d7e6cd;font-family:-apple-system,sans-serif;display:flex;justify-content:center;padding:36px 20px;box-sizing:border-box}
.page{width:100%;max-width:460px;text-align:center}
.brand{margin:0 0 20px}
.brand img{height:20px;width:auto;display:inline-block}
.scan-hint{margin:0 0 6px}
.scan-hint svg{display:block;margin:0 auto}
@media (prefers-reduced-motion: no-preference) {
  .scan-hint .wave{animation:scan-pulse 1.8s ease-in-out infinite}
  .scan-hint .wave-2{animation-delay:.2s}
  .scan-hint .wave-3{animation-delay:.4s}
}
@keyframes scan-pulse{0%,100%{opacity:.25}50%{opacity:1}}
.qr{background:#fff;border-radius:16px;padding:22px;display:inline-block}
.qr img{display:block;width:min(72vw,280px);height:min(72vw,280px)}
.breadcrumb{font-size:13.5px;color:#7c9070;margin:16px 0 4px;line-height:1.5}
.manual-note{font-size:13.5px;color:#7c9070;margin:34px 0 8px;line-height:1.5}
.values{display:flex;flex-direction:column;gap:8px;text-align:left;font-family:'DejaVu Sans Mono',monospace}
.chip{background:#10160e;border:1px solid #263420;border-radius:8px;padding:9px 12px}
.chip b{font-size:10px;letter-spacing:.06em;text-transform:uppercase;color:#7c9070;display:block;margin-bottom:3px;font-weight:400}
.chip span{font-size:12.5px;word-break:break-all}
</style></head><body><div class="page">
<div class="brand"><img src="data:image/svg+xml;base64,${LOCALSYNC_LOGO_B64}" alt="LocalSync"></div>
<!-- 2026-09-04: real feedback, live - "a visual showing a phone
     scanning the desktop screen, to hint to the user what they're
     meant to be doing with this new window." A phone outline with an
     expanding scan cone, sitting directly above the QR it's meant to
     represent scanning - hand-drawn to match this page's own existing
     icon language (plain stroked outlines, no emoji) rather than a
     generic stock graphic. -->
<div class="scan-hint" aria-hidden="true">
<svg width="64" height="52" viewBox="0 0 64 52" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect x="23" y="1" width="18" height="29" rx="3" stroke="#6fff8f" stroke-width="1.6"/>
<circle cx="32" cy="8" r="1.3" fill="#6fff8f"/>
<path class="wave wave-1" d="M20 42 L32 31 L44 42" stroke="#6fff8f" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" opacity="0.85"/>
<path class="wave wave-2" d="M12 47 L32 31 L52 47" stroke="#6fff8f" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" opacity="0.55"/>
<path class="wave wave-3" d="M4 51 L32 31 L60 51" stroke="#6fff8f" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" opacity="0.3"/>
</svg>
</div>
<div class="qr"><img src="data:image/png;base64,${QR_PNG_B64}" alt="LocalSync setup QR"></div>
<p class="breadcrumb">Phone -&gt; LocalSync app -&gt; Settings -&gt; tap QR icon</p>
<p class="manual-note">Manual values below if you'd rather type.</p>
<div class="values">
<div class="chip"><b>1. Desktop username</b><span>${LOCALSYNC_USER:-$(whoami)}</span></div>
<div class="chip"><b>2. Desktop IP address</b><span>${IP_RESULT:-not found}</span></div>
<div class="chip"><b>3. Desktop sync folder</b><span>${BARE_REPO_PATH}</span></div>
<div class="chip"><b>4. Desktop vault path</b><span>${BEST_VAULT_PATH:-(leave blank)}</span></div>
</div></div></body></html>
HTMLEOF
  if open_in_browser "$QR_HTML"; then
    echo "(Also opened in your browser - a proper window, not this terminal.)"
  fi
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
echo "${GREEN}✓ Done.${RESET}"

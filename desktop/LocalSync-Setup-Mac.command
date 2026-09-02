#!/usr/bin/env bash
# LocalSync desktop setup - macOS double-click version.
#
# 2026-09-01: real feedback - "terminal is an unknown for some users...
# a double click install file is needed for GUI only users unfamiliar
# with CLI or TUI." Finder runs any executable .command file in a new
# Terminal window on double-click - no separate app, no install, no
# terminal knowledge needed.
#
# 2026-09-01, follow-up - "download needs security and credibility...
# checksum like Linux Mint, but 1 click, not the cumbersome terminal
# command hassle." A normal checksum check means opening a terminal and
# comparing a hash by hand - exactly the hassle this file exists to
# avoid. Self-verifying instead: downloads the real setup.sh, computes
# its own SHA256, and only runs it if that matches EXPECTED_SHA256
# below - real tamper detection, zero extra steps for the user. The
# check is deliberately printed out loud (not silent) - also an honest
# moment to show a new user what "verify before you run it" actually
# looks like, not just tell them to do it.
#
# Real bug caught testing this, live: capturing the download into a
# shell variable ($(...)) silently strips the trailing newline, which
# changes the hash - every legitimate run would have failed the check.
# Downloads to a real temp file and hashes that instead, matching
# exactly what `sha256sum`/`shasum` on the original file produces.
#
# MAINTENANCE: EXPECTED_SHA256 must be updated (shasum -a 256 setup.sh)
# every time setup.sh's content changes, or this will always refuse to
# run - a deliberate fail-closed default, not a bug.

set -uo pipefail
EXPECTED_SHA256="d06b7932ba20371cbddc631b0a3ec0be6b714c41480888e31ae86bf03f9007ca"
SCRIPT_URL="https://raw.githubusercontent.com/eiger3970/localsync/main/desktop/setup.sh"

echo "LocalSync desktop setup"
echo "========================"
echo

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

echo "Downloading setup.sh..."
if ! curl -fsSL "$SCRIPT_URL" -o "$TMPFILE"; then
  echo "Download failed - check your internet connection and try again." >&2
  read -r -p "Press Enter to close this window..."
  exit 1
fi

echo "Verifying integrity (SHA256 checksum, so you're not running a"
echo "tampered or corrupted copy)..."
ACTUAL_SHA256="$(shasum -a 256 "$TMPFILE" | cut -d' ' -f1)"

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo
  echo "CHECKSUM MISMATCH - refusing to run this script."
  echo "  Expected: $EXPECTED_SHA256"
  echo "  Got:      $ACTUAL_SHA256"
  echo
  echo "This means the downloaded script doesn't match what LocalSync"
  echo "published - it may have been tampered with, or this file itself"
  echo "is out of date. Do not proceed. Get the current file from"
  echo "https://kworld.space/localsync and try again."
  read -r -p "Press Enter to close this window..."
  exit 1
fi
echo "Verified - checksum matches. Safe to run."
echo

bash "$TMPFILE" "$@"
status=$?

echo
if [[ $status -eq 0 ]]; then
  echo "Done. Copy the bare repo path above into LocalSync's Settings on your phone."
else
  echo "Something went wrong (exit code $status) - see the messages above."
fi
echo
read -r -p "Press Enter to close this window..."

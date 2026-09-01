#!/usr/bin/env bash
# LocalSync desktop setup - macOS double-click version.
#
# 2026-09-01: real feedback - "terminal is an unknown for some users...
# a double click install file is needed for GUI only users unfamiliar
# with CLI or TUI." Finder runs any executable .command file in a new
# Terminal window on double-click - no separate app, no install, no
# terminal knowledge needed. This is a thin wrapper, not a duplicate of
# the real logic: it fetches the actual, current setup.sh straight from
# the website and runs it, so there's exactly one place (setup.sh) that
# ever needs updating - this file and its Linux sibling
# (LocalSync-Setup-Linux.desktop) never go stale on their own.
#
# The trailing "Press Enter to close" pause is deliberate - Terminal.app
# closes the window the instant the script exits by default, which
# would hide any real error (or the bare repo path the user needs to
# copy into Settings) before it could be read.

set -uo pipefail
echo "LocalSync desktop setup"
echo "========================"
echo

curl -fsSL https://kworld.space/localsync/setup.sh | bash
status=$?

echo
if [[ $status -eq 0 ]]; then
  echo "Done. Copy the bare repo path above into LocalSync's Settings on your phone."
else
  echo "Something went wrong (exit code $status) - see the messages above."
fi
echo
read -r -p "Press Enter to close this window..."

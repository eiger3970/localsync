#!/bin/bash
# desktop/localsync_sync.sh — LocalSync desktop-side sync
#
# 2026-08-27: real gap, confirmed in docs/desktop-setup.md's own words -
# "Today the desktop side of the sync ... is manual, run by hand.
# Nothing automated exists for it yet." This is that automation.
#
# Adapted from the user's own real, battle-tested synco.sh
# (~/Documents/Scripts/synco.sh - years of real-world refinement per
# this project's own memory) rather than written from scratch: same
# lock file, same log style, same four-way fetch/compare/sync logic,
# same repair_conflicts.py for markdown/Kanban conflicts (LocalSync's
# own Dart-side conflict_repair.dart already ports that script's exact
# output format near-verbatim, confirmed by reading it directly - reuse
# it as-is here rather than risk drifting the two apart).
#
# Two real differences from synco.sh, both because this is a general
# LocalSync desktop script for any user's own vault path, not one
# person's fixed Obsidian_vault:
#   1. VAULT/BARE_REPO/REPAIR_PY are configured, not hardcoded - see
#      the config section just below.
#   2. Conflicts on any non-.md file (Tier 0's whole reason to exist -
#      plain files, no PKM) get the SAME safety net LocalSync's phone
#      app now has (sync_service.dart's repairBinaryConflictsOnDisk,
#      2026-08-27) - back up both sides, keep "ours", never leave a
#      binary conflict for git's raw merge output to guess at. Same
#      backup folder/naming convention as the phone side
#      (LocalSync/Conflict Backups/<name> - yours|<label> - <ts>.<ext>)
#      so either side's backups are discoverable from either device.
set -euo pipefail

# ── Config - override via environment, or edit these defaults ────────────────
# Matches docs/desktop-setup.md's documented bare-repo convention.
VAULT="${LOCALSYNC_VAULT:-$HOME/Documents/LocalSync/vault}"
BARE_REPO="${LOCALSYNC_BARE_REPO:-$HOME/Documents/Git/LocalSync/vault.git}"
BRANCH="${LOCALSYNC_BRANCH:-main}"
LOG="${LOCALSYNC_LOG:-$HOME/.localsync_sync.log}"
LOCK="/tmp/localsync_sync.lock"
# Reuses the user's own proven repair script directly rather than a
# forked copy - override if this repo is checked out somewhere else.
REPAIR_PY="${LOCALSYNC_REPAIR_PY:-$HOME/Documents/Scripts/repair_conflicts.py}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
die() { log "FATAL: $*"; exit 1; }

# ── Lock: one run at a time ───────────────────────────────────────────────────
exec 9>"$LOCK"
flock -n 9 || { log "Already running — skipping"; exit 0; }

# ── Bootstrap: clone the working copy on first run ────────────────────────────
# docs/desktop-setup.md only ever documented creating the bare repo -
# nothing clones a working copy from it. First run does that instead of
# requiring a separate manual step.
if [[ ! -d "$VAULT" ]]; then
  [[ -d "$BARE_REPO" ]] || die "Bare repo not found: $BARE_REPO (see docs/desktop-setup.md)"
  mkdir -p "$(dirname "$VAULT")"
  git clone "$BARE_REPO" "$VAULT" || die "Clone failed: $BARE_REPO -> $VAULT"
  log "First run - cloned working copy from $BARE_REPO"
fi

[[ -d "$VAULT/.git" ]] || die "Not a git repo: $VAULT"
command -v python3 >/dev/null || die "python3 not found"
[[ -f "$REPAIR_PY" ]] || die "repair_conflicts.py missing: $REPAIR_PY"

cd "$VAULT" || die "Cannot cd to $VAULT"
log "=== localsync_sync start ==="

# ── Repair markdown/Kanban conflict markers ───────────────────────────────────
repair_md_conflicts() {
  local repaired=0
  while IFS= read -r -d '' file; do
    log "  ⚠ Conflict markers: $file"
    rc=0; python3 "$REPAIR_PY" "$file" || rc=$?
    if [[ "$rc" = "2" ]]; then
      log "  ✓ Repaired: $file"
      repaired=1
    elif [[ "$rc" = "0" ]]; then
      log "  ⚠ grep matched $file but python found no complete markers — check manually"
    else
      log "  ERROR: repair failed for $file (exit $rc) — markers left for manual fix"
    fi
  done < <(grep -rlZ --include="*.md" --exclude-dir=.git "^<<<<<<< " . 2>/dev/null || true)

  if [[ "$repaired" = "1" ]]; then
    git add -- '*.md'
    # Mid-merge, staging and leaving the actual commit to
    # finish_merge_if_ready (called once, after every repair pass has
    # run) - committing here directly would risk git's own hard refusal
    # ("you have unmerged files") if a whole-file conflict is still
    # pending in the same merge. Outside a merge (the plain repair pass
    # at script start, stray markers with no active merge at all),
    # there's no finish_merge_if_ready to rely on, so commit directly.
    if [[ ! -f ".git/MERGE_HEAD" ]] && ! git diff --cached --quiet; then
      git commit -m "Merge conflicts (both sides kept) $(date '+%Y-%m-%d %H:%M:%S')"
      log "  ✓ Markdown repair committed"
    fi
  fi
}

# ── Back up and resolve conflicts on any non-.md file ─────────────────────────
# Mirrors sync_service.dart's repairBinaryConflictsOnDisk exactly - same
# backup folder, same filename shape, same "keep ours" default. A real
# conflict on a binary/generic file can't be text-merged or wrapped in a
# callout, so this is the whole-file equivalent of the markdown repair
# above, not an afterthought.
repair_binary_conflicts() {
  local backup_dir="$VAULT/LocalSync/Conflict Backups"
  local resolved=0
  while IFS= read -r -d '' path; do
    [[ "$path" == *.md ]] && continue
    mkdir -p "$backup_dir"
    local base ts stem ext
    base="$(basename "$path")"
    ts="$(date '+%Y%m%d%H%M')"
    if [[ "$base" == *.* && "$base" != .* ]]; then
      stem="${base%.*}"
      ext=".${base##*.}"
    else
      stem="$base"
      ext=""
    fi

    local has_ours=0 has_theirs=0
    if git show ":2:$path" > "$backup_dir/$stem - yours - $ts$ext" 2>/dev/null; then
      has_ours=1
    else
      rm -f "$backup_dir/$stem - yours - $ts$ext"
    fi
    if git show ":3:$path" > "$backup_dir/$stem - $SYNCO_OTHER_LABEL - $ts$ext" 2>/dev/null; then
      has_theirs=1
    else
      rm -f "$backup_dir/$stem - $SYNCO_OTHER_LABEL - $ts$ext"
    fi

    if [[ "$has_ours" = "1" ]]; then
      cp "$backup_dir/$stem - yours - $ts$ext" "$path"
    elif [[ "$has_theirs" = "1" ]]; then
      cp "$backup_dir/$stem - $SYNCO_OTHER_LABEL - $ts$ext" "$path"
    else
      continue # both sides deleted it - nothing to keep, leave as-is
    fi
    git add -- "$path"
    log "  ✓ Whole-file conflict resolved (kept yours, backed up both): $path"
    resolved=1
  done < <(git diff --name-only --diff-filter=U -z 2>/dev/null || true)
  # 2026-08-27: real bug, found by actually running this against a real
  # conflict, not just reading it - a bare `[[ cond ]] && cmd` as a
  # function's LAST statement makes the function's own return status be
  # the test's status whenever cond is false (1, "failure"), which
  # set -e treats as a real error and kills the whole script with no
  # visible error message at all. `if/fi` (used here and everywhere
  # else in this file) doesn't have this problem - only this one bare
  # shorthand did.
  if [[ "$resolved" = "1" ]]; then
    log "  (whole-file conflicts staged - finish_merge_if_ready commits them)"
  fi
}

# 2026-08-27: real bug found and fixed while actually testing this
# against a genuine binary conflict (not just reading the code) -
# resolving to "ours" and staging it produces ZERO diff against HEAD
# whenever HEAD already IS "ours" mid-merge, which is always true here.
# The old per-repair-function "commit if git diff --cached isn't empty"
# check (still fine for repair_md_conflicts, which always rewrites
# content) silently no-op'd for a resolved-but-identical-to-HEAD binary
# conflict, leaving MERGE_HEAD stuck even though the conflict itself was
# genuinely, correctly resolved on disk. A second, related risk this
# also avoids: if BOTH a markdown AND a whole-file conflict exist in the
# same merge, letting repair_md_conflicts commit on its own the moment
# it finishes would hit git's own hard refusal ("you have unmerged
# files") while the binary conflict is still pending - committing only
# happens here, once, after every repair pass has had its turn.
finish_merge_if_ready() {
  [[ -f ".git/MERGE_HEAD" ]] || return 0
  [[ -z "$(git diff --name-only --diff-filter=U)" ]] || return 0
  git commit --no-edit
  log "  ✓ Merge commit finalized"
}

repair_conflicts() {
  repair_md_conflicts
  repair_binary_conflicts
  finish_merge_if_ready
}

# ── Recover from a previous crashed mid-merge ─────────────────────────────────
if [[ -f ".git/MERGE_HEAD" ]]; then
  log "⚠ Stuck MERGE_HEAD from previous run — resuming..."
  repair_conflicts
  if [[ -f ".git/MERGE_HEAD" ]]; then
    die "Repair incomplete after resuming a stuck merge — real conflicts remain. Run: git status"
  fi
fi

repair_conflicts

# ── Commit local desktop changes ──────────────────────────────────────────────
git add .
if git diff --cached --quiet; then
  log "No desktop changes to commit"
else
  git commit -m "Desktop sync $(date '+%Y-%m-%d %H:%M:%S')"
  log "Committed desktop changes"
fi

# ── Fetch bare repo ────────────────────────────────────────────────────────────
if ! git fetch origin 2>&1 | tee -a "$LOG"; then
  die "fetch failed — bare repo unreachable or SSH down"
fi
log "Fetched from bare repo"
export SYNCO_OTHER_LABEL=$(git log -1 --format=%s "origin/$BRANCH" 2>/dev/null || echo "other device")
export SYNCO_OTHER_TIME=$(git log -1 --format=%cd --date=format:"%Y-%m-%d %H:%M" "origin/$BRANCH" 2>/dev/null || echo "")

# ── Compare and sync ───────────────────────────────────────────────────────────
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$BRANCH")
BASE=$(git merge-base HEAD "origin/$BRANCH")

push_with_retry() {
  if git push origin "$BRANCH"; then
    return 0
  fi
  log "  ⚠ Push rejected — re-fetching and retrying once..."
  git fetch origin
  REMOTE_NOW=$(git rev-parse "origin/$BRANCH")
  if git merge --ff-only "$REMOTE_NOW" 2>/dev/null; then
    git push origin "$BRANCH" || die "Push failed after retry"
  else
    die "Could not fast-forward after retry — manual intervention needed"
  fi
}

if [[ "$LOCAL" = "$REMOTE" ]]; then
  log "✓ Already in sync"

elif [[ "$LOCAL" = "$BASE" ]]; then
  git merge --ff-only "origin/$BRANCH"
  log "↓ Updated desktop from bare repo"
  repair_conflicts

elif [[ "$REMOTE" = "$BASE" ]]; then
  push_with_retry
  log "↑ Pushed desktop changes to bare repo"

else
  log "⚡ Diverged — merging..."
  if git merge --no-ff -m "Merge desktop and phone $(date '+%Y-%m-%d %H:%M:%S')" "origin/$BRANCH"; then
    repair_conflicts
  else
    log "  Merge conflict — repairing (both sides kept)..."
    repair_conflicts
    if [[ -f ".git/MERGE_HEAD" ]]; then
      die "Repair incomplete — MERGE_HEAD still present. Run: git merge --abort"
    fi
  fi
  push_with_retry
  log "✓ Merged and pushed"
fi

log "=== localsync_sync complete ==="

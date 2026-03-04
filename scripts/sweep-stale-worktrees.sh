#!/usr/bin/env bash
# sweep-stale-worktrees.sh — Remove worktree directories for completed features.
#
# Reads metadata/worktree-registry.json and cleans up worktree dirs for
# entries with status "complete" whose directory still exists under worktrees/.
# Also reports orphaned worktree dirs (on disk but missing from registry) as
# log-only candidates — never auto-deletes registry-unknown features.
#
# Usage: sweep-stale-worktrees.sh [--quiet]
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
REGISTRY="$WORKSPACE_ROOT/metadata/worktree-registry.json"
WORKTREES_ROOT="$WORKSPACE_ROOT/worktrees"
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

log() {
  if [[ "$QUIET" != "true" ]]; then
    echo "$@"
  fi
}

if [[ ! -f "$REGISTRY" ]]; then
  log "sweep-stale-worktrees.sh: no registry found at $REGISTRY — skipping"
  exit 0
fi

if ! command -v jq &>/dev/null; then
  log "sweep-stale-worktrees.sh: jq not found — skipping"
  exit 0
fi

if [[ ! -d "$WORKTREES_ROOT" ]]; then
  log "sweep-stale-worktrees.sh: no worktrees dir at $WORKTREES_ROOT — nothing to do"
  exit 0
fi

cleaned=0
orphans=0

# Sweep registry entries with status "complete" that still have a worktree dir
while IFS= read -r feature; do
  [[ -z "$feature" ]] && continue
  FEATURE_DIR="$WORKTREES_ROOT/$feature"
  if [[ -d "$FEATURE_DIR" ]]; then
    log "Sweeping completed feature: $feature"
    if [[ -f "$WORKSPACE_ROOT/scripts/cleanup-worktrees.sh" ]]; then
      if [[ "$QUIET" == "true" ]]; then
        "$WORKSPACE_ROOT/scripts/cleanup-worktrees.sh" "$feature" --remove-branches > /dev/null 2>&1 || true
      else
        "$WORKSPACE_ROOT/scripts/cleanup-worktrees.sh" "$feature" --remove-branches || true
      fi
    else
      log "  Warning: cleanup-worktrees.sh not found — skipping $feature"
    fi
    cleaned=$((cleaned + 1))
  fi
done < <(jq -r '.worktrees[] | select(.status == "complete") | .feature' "$REGISTRY" 2>/dev/null || true)

# Report orphaned dirs (on disk but not in registry) — log only, do not delete
for d in "$WORKTREES_ROOT"/*/; do
  [[ -d "$d" ]] || continue
  feature="$(basename "$d")"
  [[ "$feature" == ".archive" ]] && continue
  in_registry=$(jq -r --arg f "$feature" \
    '[.worktrees[] | select(.feature == $f)] | length' \
    "$REGISTRY" 2>/dev/null || echo 0)
  if [[ "$in_registry" == "0" ]]; then
    log "Orphan (not in registry): $WORKTREES_ROOT/$feature — inspect manually"
    orphans=$((orphans + 1))
  fi
done

log "sweep-stale-worktrees.sh: cleaned=$cleaned orphans(logged only)=$orphans"

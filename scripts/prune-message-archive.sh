#!/usr/bin/env bash
# prune-message-archive.sh — Age-based pruning of archived inbox messages.
#
# Removes archived messages older than the configured retention period.
# Never touches live inbox directories (metadata/messages/*).
#
# Agent archives (lead, author-*, reviewer): default 7-day retention.
# Human archive: default 14-day retention.
#
# Usage: prune-message-archive.sh [--agent-days 7] [--human-days 14] [--dry-run] [--quiet]
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
ARCHIVE_ROOT="$WORKSPACE_ROOT/metadata/archive/messages"
AGENT_DAYS=7
HUMAN_DAYS=14
DRY_RUN=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-days) AGENT_DAYS="$2"; shift 2 ;;
    --human-days) HUMAN_DAYS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --quiet) QUIET=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

log() {
  if [[ "$QUIET" != "true" ]]; then
    echo "$@"
  fi
}

if [[ ! -d "$ARCHIVE_ROOT" ]]; then
  log "prune-message-archive.sh: no archive at $ARCHIVE_ROOT — nothing to prune"
  exit 0
fi

pruned=0
now_epoch=$(date +%s)

prune_dir() {
  local dir="$1"
  local max_days="$2"
  local cutoff=$(( now_epoch - max_days * 86400 ))
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    # Portable mtime: macOS uses stat -f%m, Linux uses stat -c%Y
    local mtime
    mtime=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)
    if (( mtime < cutoff )); then
      if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] would delete: $f"
      else
        rm "$f"
        pruned=$((pruned + 1))
        log "  deleted: $f"
      fi
    fi
  done
}

# Agent archives: lead, author-*, reviewer
for dir in "$ARCHIVE_ROOT"/lead "$ARCHIVE_ROOT"/reviewer; do
  [[ -d "$dir" ]] || continue
  log "Pruning agent archive: $dir (>=${AGENT_DAYS}d)"
  prune_dir "$dir" "$AGENT_DAYS"
done
for dir in "$ARCHIVE_ROOT"/author-*/; do
  [[ -d "$dir" ]] || continue
  log "Pruning agent archive: $dir (>=${AGENT_DAYS}d)"
  prune_dir "$dir" "$AGENT_DAYS"
done

# Human archive
if [[ -d "$ARCHIVE_ROOT/human" ]]; then
  log "Pruning human archive: $ARCHIVE_ROOT/human (>=${HUMAN_DAYS}d)"
  prune_dir "$ARCHIVE_ROOT/human" "$HUMAN_DAYS"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "prune-message-archive.sh: dry-run complete"
else
  log "prune-message-archive.sh: pruned=$pruned message(s)"
fi

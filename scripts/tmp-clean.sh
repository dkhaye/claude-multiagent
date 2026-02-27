#!/usr/bin/env bash
# tmp-clean.sh — Remove stale temp files left by previous agent sessions.
# Called by launch-agents.sh at startup (before any agents are running).
#
# Usage:
#   tmp-clean.sh [options]
#
# Options:
#   --beads           Clean tmp/beads/ (Beads task description temp files)
#   --session         Clean tmp/session/ (per-agent session temp files)
#   --all             Clean both (default if neither --beads nor --session given)
#   --older-than N    Only remove files older than N days (default: 1)
#   --quiet           Suppress per-file output
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

CLEAN_BEADS=false
CLEAN_SESSION=false
OLDER_THAN=1
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --beads)      CLEAN_BEADS=true; shift ;;
    --session)    CLEAN_SESSION=true; shift ;;
    --all)        CLEAN_BEADS=true; CLEAN_SESSION=true; shift ;;
    --older-than) OLDER_THAN="$2"; shift 2 ;;
    --quiet)      QUIET=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Default: clean both if neither specified
if ! $CLEAN_BEADS && ! $CLEAN_SESSION; then
  CLEAN_BEADS=true
  CLEAN_SESSION=true
fi

TMP_ROOT="$WORKSPACE_ROOT/metadata/tmp"
CLEANED=0

clean_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' f; do
    rm -f "$f"
    $QUIET || echo "  removed: $f"
    CLEANED=$((CLEANED + 1))
  done < <(find "$dir" -maxdepth 2 -type f -name "*.md" -mtime "+${OLDER_THAN}" -print0 2>/dev/null)
}

$QUIET || echo "tmp-clean: scanning files older than ${OLDER_THAN} day(s) ..."

if $CLEAN_BEADS;   then clean_dir "$TMP_ROOT/beads";   fi
if $CLEAN_SESSION; then clean_dir "$TMP_ROOT/session"; fi

$QUIET || echo "tmp-clean: done — removed $CLEANED file(s)."

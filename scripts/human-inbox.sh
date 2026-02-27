#!/usr/bin/env bash
# human-inbox.sh — Read, list, or archive messages in metadata/messages/human/.
#
# Usage:
#   human-inbox.sh              # Display all pending messages (default)
#   human-inbox.sh --list       # List filenames only
#   human-inbox.sh --count      # Print count of pending messages and exit
#   human-inbox.sh --archive    # Move all messages to .archive/ subdirectory
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

INBOX="$WORKSPACE_ROOT/metadata/messages/human"
ARCHIVE="$INBOX/.archive"
MODE="read"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)    MODE="list";    shift ;;
    --archive) MODE="archive"; shift ;;
    --count)   MODE="count";   shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$INBOX"

# Collect messages sorted by filename (chronological by timestamp prefix)
mapfile -t MESSAGES < <(find "$INBOX" -maxdepth 1 -name "*.md" | sort)
COUNT="${#MESSAGES[@]}"

case "$MODE" in
  count)
    echo "$COUNT"
    ;;

  list)
    if [[ "$COUNT" -eq 0 ]]; then
      echo "(no messages)"
    else
      for f in "${MESSAGES[@]}"; do
        echo "$(basename "$f")"
      done
    fi
    ;;

  read)
    if [[ "$COUNT" -eq 0 ]]; then
      echo "Human inbox is empty."
      exit 0
    fi
    echo "======================================"
    echo "  Human inbox — ${COUNT} message(s)"
    echo "======================================"
    echo ""
    for f in "${MESSAGES[@]}"; do
      echo "--- $(basename "$f") ---"
      cat "$f"
      echo ""
    done
    echo "======================================"
    echo ""
    echo "To archive these messages: $(basename "$0") --archive"
    ;;

  archive)
    if [[ "$COUNT" -eq 0 ]]; then
      echo "Nothing to archive — inbox is empty."
      exit 0
    fi
    mkdir -p "$ARCHIVE"
    for f in "${MESSAGES[@]}"; do
      mv "$f" "$ARCHIVE/"
    done
    echo "Archived ${COUNT} message(s) to ${ARCHIVE}/"
    ;;
esac

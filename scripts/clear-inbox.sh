#!/usr/bin/env bash
# clear-inbox.sh — Remove all processed .md messages from an agent's inbox directory.
# Leaves .gitkeep in place. Safe to run even if the inbox is already empty.
# Usage: clear-inbox.sh <agent-name>
set -euo pipefail
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
AGENT="${1:?Usage: clear-inbox.sh <agent-name>}"
INBOX_DIR="$WORKSPACE_ROOT/metadata/messages/$AGENT"
[[ -d "$INBOX_DIR" ]] || { echo "Inbox not found: $INBOX_DIR"; exit 1; }
count=0
for f in "$INBOX_DIR"/*.md; do
  [[ -e "$f" ]] || continue
  [[ "$f" == *".gitkeep" ]] && continue
  rm "$f" && count=$((count + 1))
done
echo "Cleared $count message(s) from $AGENT inbox."

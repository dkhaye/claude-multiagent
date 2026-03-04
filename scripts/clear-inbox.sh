#!/usr/bin/env bash
# clear-inbox.sh — Archive specific processed inbox message files.
# Pass the exact file paths you have already read and processed.
#
# This is TOCTOU-safe: only archives files you explicitly name.
# New messages that arrive after you started reading are untouched.
#
# Messages are moved (not deleted) to metadata/archive/messages/<agent>/
# so they can be audited. Deletion happens later via prune-message-archive.sh.
#
# Usage: clear-inbox.sh <file1.md> [file2.md] ...
# Example:
#   clear-inbox.sh \
#     ~/projects/[[PROJECT_NAME]]/metadata/messages/lead/20260227-130000-cc-task.md \
#     ~/projects/[[PROJECT_NAME]]/metadata/messages/lead/20260227-131500-author-1-done.md
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: clear-inbox.sh <file1.md> [file2.md] ..."
  exit 1
fi

count=0
for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    echo "Skipping (not found): $f"
    continue
  fi
  if [[ "$f" != *.md ]]; then
    echo "Skipping (not .md): $f"
    continue
  fi
  # Derive archive dir: same structure under metadata/archive/messages/<agent>/
  INBOX_DIR="$(dirname "$f")"
  AGENT_NAME="$(basename "$INBOX_DIR")"
  METADATA_DIR="$(dirname "$(dirname "$INBOX_DIR")")"
  ARCHIVE_DIR="$METADATA_DIR/archive/messages/$AGENT_NAME"
  mkdir -p "$ARCHIVE_DIR"
  mv "$f" "$ARCHIVE_DIR/"
  count=$((count + 1))
done

echo "Archived $count message(s)."

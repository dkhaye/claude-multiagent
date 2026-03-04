#!/usr/bin/env bash
# clear-inbox.sh — Process specific files: delete temp files, archive inbox messages.
# Pass the exact file paths you have already read and processed.
#
# This is TOCTOU-safe: only processes files you explicitly name.
# New messages that arrive after you started reading are untouched.
#
# Behavior depends on the file's location:
#   .global/tmp/*.md          -> deleted immediately (throwaway commit messages / PR bodies)
#   metadata/messages/*/*.md  -> moved to metadata/archive/messages/<agent>/ for audit trail
#                               Deletion of archived files happens later via prune-message-archive.sh
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
  INBOX_DIR="$(dirname "$f")"

  # Global CC temp files (.global/tmp) are deleted, not archived
  if [[ "$INBOX_DIR" == *"/.global/tmp" ]]; then
    rm "$f"
    count=$((count + 1))
    continue
  fi

  # Project inbox messages are archived for audit trail
  AGENT_NAME="$(basename "$INBOX_DIR")"
  METADATA_DIR="$(dirname "$(dirname "$INBOX_DIR")")"
  ARCHIVE_DIR="$METADATA_DIR/archive/messages/$AGENT_NAME"
  mkdir -p "$ARCHIVE_DIR"
  mv "$f" "$ARCHIVE_DIR/"
  count=$((count + 1))
done

echo "Processed $count file(s)."

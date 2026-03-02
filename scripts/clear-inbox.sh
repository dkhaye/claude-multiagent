#!/usr/bin/env bash
# clear-inbox.sh — Delete specific processed inbox message files.
# Pass the exact file paths you have already read and processed.
#
# This is TOCTOU-safe: only deletes files you explicitly name.
# New messages that arrive after you started reading are untouched.
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
  rm "$f"
  count=$((count + 1))
done

echo "Deleted $count message(s)."

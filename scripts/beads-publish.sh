#!/usr/bin/env bash
# beads-publish.sh — Create and publish a Beads task in one step.
# Usage: beads-publish.sh "<task title>" <desc-file>
#
# Creates the Beads issue atomically with the description, deletes the
# temp file, and echoes the issue ID to stdout.
#
# Uses bd create --body-file to create title + description in one command,
# eliminating the window where a bare-title issue would appear in bd ready
# before the description is attached.
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

TITLE="${1:-}"
DESC_FILE="${2:-}"

if [[ -z "$TITLE" || -z "$DESC_FILE" ]]; then
  echo "Usage: beads-publish.sh \"<task title>\" <desc-file>" >&2
  exit 1
fi

if [[ ! -f "$DESC_FILE" ]]; then
  echo "Error: description file not found: $DESC_FILE" >&2
  exit 1
fi

ISSUE_ID=$(bd create "$TITLE" --body-file "$DESC_FILE")
rm -f "$DESC_FILE"
echo "$ISSUE_ID"

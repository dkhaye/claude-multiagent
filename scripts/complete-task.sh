#!/usr/bin/env bash
# complete-task.sh — Close a Beads task and send a completion message to Lead.
#
# Replaces the manual 3-step completion sequence:
#   1. bd close <id>
#   2. Write completion message file
#   3. (optional) attach evidence
#
# Usage:
#   complete-task.sh <beads-id> <pr-url-or-none> <author-n> [<brief-summary>]
#   complete-task.sh <beads-id> <pr-url-or-none> <author-n> [<brief-summary>] --evidence-file <path>
#
# Arguments:
#   beads-id        Beads issue ID, e.g. beads-central-9pr
#   pr-url          Full GitHub PR URL, or the literal string "none" if no PR
#   author-n        Author number (1, 2, or 3)
#   summary         Optional one-line task summary (defaults to "Task <beads-id>")
#   --evidence-file Path to a markdown file whose contents are appended to the
#                   completion message under an "## Evidence" heading.
#
# Examples:
#   complete-task.sh beads-central-9pr https://github.com/nytimes/.../pull/19 1
#   complete-task.sh beads-central-abc none 2 "Fix checkov skip annotations"
#   complete-task.sh beads-central-xyz https://github.com/.../pull/5 1 "Add IAM role" \
#     --evidence-file $WORKSPACE_ROOT/metadata/tmp/session/author-1/evidence-20240101.md
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

# Parse args: strip --evidence-file flag, collect positional args
EVIDENCE_FILE=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence-file) EVIDENCE_FILE="$2"; shift 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

BEADS_ID="${POSITIONAL[0]:-}"
PR_URL="${POSITIONAL[1]:-}"
AUTHOR_N="${POSITIONAL[2]:-}"
SUMMARY="${POSITIONAL[3]:-Task ${BEADS_ID}}"

if [[ -z "$BEADS_ID" || -z "$PR_URL" || -z "$AUTHOR_N" ]]; then
  echo "Usage: complete-task.sh <beads-id> <pr-url-or-none> <author-n> [summary] [--evidence-file <path>]" >&2
  exit 1
fi

# 1. Close the Beads issue
bd close "$BEADS_ID"
echo "Closed Beads task ${BEADS_ID}" >&2

# 2. Write completion message to Lead inbox
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MSG_DIR="$WORKSPACE_ROOT/metadata/messages/lead"
MSG_FILE="${MSG_DIR}/${TIMESTAMP}-author-${AUTHOR_N}-complete.md"

printf '## From Author-%s — Task complete\nTask: %s\nPR: %s\nBeads: %s\n' \
  "$AUTHOR_N" "$SUMMARY" "$PR_URL" "$BEADS_ID" > "$MSG_FILE"

# 3. Append evidence if provided
if [[ -n "$EVIDENCE_FILE" ]]; then
  if [[ ! -f "$EVIDENCE_FILE" ]]; then
    echo "Warning: --evidence-file not found: $EVIDENCE_FILE" >&2
  else
    printf '\n## Evidence\n' >> "$MSG_FILE"
    cat "$EVIDENCE_FILE" >> "$MSG_FILE"
    echo "Evidence appended from ${EVIDENCE_FILE}" >&2
  fi
fi

echo "Completion message → ${MSG_FILE}" >&2
echo "Done. Run 'bd ready' to claim the next task." >&2

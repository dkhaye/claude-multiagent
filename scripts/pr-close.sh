#!/usr/bin/env bash
# pr-close.sh — Remove a PR from metadata/open-prs.json and notify the human inbox.
# Run after a PR is merged, closed, or abandoned.
#
# Usage:
#   pr-close.sh --repo <org/repo> --number <N> [--reason <merged|closed|abandoned>]
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

REPO=""
NUMBER=""
REASON="merged"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="$2";   shift 2 ;;
    --number) NUMBER="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" || -z "$NUMBER" ]]; then
  echo "Usage: pr-close.sh --repo <org/repo> --number <PR-number> [--reason merged|closed|abandoned]" >&2
  exit 1
fi

PRS_FILE="$WORKSPACE_ROOT/metadata/open-prs.json"
if [[ ! -f "$PRS_FILE" ]]; then
  echo "No open-prs.json at $PRS_FILE — nothing to remove."
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)" >&2
  exit 1
fi

# Look up the PR entry before removing (for the inbox message)
TITLE=$(jq -r --arg repo "$REPO" --argjson num "$NUMBER" \
  '.prs[] | select(.repo == $repo and .number == $num) | .title' "$PRS_FILE")
URL=$(jq -r --arg repo "$REPO" --argjson num "$NUMBER" \
  '.prs[] | select(.repo == $repo and .number == $num) | .url' "$PRS_FILE")

# Remove from registry
tmp="$(mktemp)"
jq --arg repo "$REPO" --argjson num "$NUMBER" \
  '.prs = [.prs[] | select(.repo != $repo or .number != $num)]' \
  "$PRS_FILE" > "$tmp"
mv "$tmp" "$PRS_FILE"
echo "Removed PR #${NUMBER} ($REPO) from open-prs.json"

# Write notification to human inbox
INBOX="$WORKSPACE_ROOT/metadata/messages/human"
mkdir -p "$INBOX"
MSG_FILE="$INBOX/$(date +%Y%m%d-%H%M%S)-pr-${REASON}-$(echo "$REPO" | tr '/' '-')-${NUMBER}.md"
printf '## PR %s: #%s — %s\nRepo:   %s\nPR:     #%s\nURL:    %s\nReason: %s\nTime:   %s\n' \
  "$REASON" "$NUMBER" "${TITLE:-$REPO}" \
  "$REPO" "$NUMBER" "${URL:-(unknown)}" \
  "$REASON" "$(date '+%Y-%m-%d %H:%M:%S')" \
  > "$MSG_FILE"
echo "Notified human inbox: $MSG_FILE"

#!/usr/bin/env bash
# post-to-slack.sh — Post a human inbox message to Slack via incoming webhook.
#
# Usage:
#   post-to-slack.sh <message-file>
#
# Config: ~/projects/.global/config/slack.conf must define SLACK_WEBHOOK_URL.
# Gracefully no-ops (exit 0) if config is missing or SLACK_WEBHOOK_URL is unset.
#
# Markdown → Slack mrkdwn conversions:
#   [text](url)    →  <url|text>   (clickable links)
#   # / ## / ###   →  *Heading*    (bold headers)
#   **bold**       →  *bold*
#
# Requires: curl, jq
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="${WORKSPACE_ROOT##*/}"

SLACK_CONF="$HOME/projects/.global/config/slack.conf"
MSG_FILE="${1:-}"

if [[ -z "$MSG_FILE" ]]; then
  printf 'Usage: post-to-slack.sh <message-file>\n' >&2; exit 1
fi
if [[ ! -f "$MSG_FILE" ]]; then
  printf 'post-to-slack: file not found: %s\n' "$MSG_FILE" >&2; exit 1
fi

# Load config — graceful no-op if missing
if [[ ! -f "$SLACK_CONF" ]]; then
  printf 'post-to-slack: no config at %s — Slack notification skipped.\n' "$SLACK_CONF" >&2
  exit 0
fi
# shellcheck source=/dev/null
source "$SLACK_CONF"
if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  printf 'post-to-slack: SLACK_WEBHOOK_URL not set — skipped.\n' >&2; exit 0
fi

# Label: strip 16-char timestamp prefix from filename (YYYYMMDD-HHMMSS-)
BASENAME="$(basename "$MSG_FILE" .md)"
SENDER_SUBJECT="${BASENAME:16}"

# Markdown → Slack mrkdwn
BODY="$(sed \
  -e 's/\[\([^]]*\)\](\([^)]*\))/<\2|\1>/g' \
  -e 's/^### \(.*\)$/*\1*/g' \
  -e 's/^## \(.*\)$/*\1*/g' \
  -e 's/^# \(.*\)$/*\1*/g' \
  -e 's/\*\*\([^*]*\)\*\*/*\1*/g' \
  "$MSG_FILE")"

# Truncate to stay under Slack's ~4000-char text limit
if [[ ${#BODY} -gt 3800 ]]; then
  BODY="${BODY:0:3800}
…(truncated — full message: metadata/messages/human/${BASENAME}.md)"
fi

FULL_TEXT="*[${PROJECT_NAME}]* ${SENDER_SUBJECT}

${BODY}"

PAYLOAD="$(jq --null-input --arg text "$FULL_TEXT" '{"text": $text}')"

# Non-fatal POST — Slack downtime must not break the Lead session
if ! curl --silent \
     -X POST -H 'Content-type: application/json' \
     --data "$PAYLOAD" \
     "$SLACK_WEBHOOK_URL"; then
  printf 'post-to-slack: WARNING: POST failed — continuing.\n' >&2
fi

printf 'post-to-slack: posted [%s] %s\n' "$PROJECT_NAME" "$BASENAME" >&2

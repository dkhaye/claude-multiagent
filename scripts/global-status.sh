#!/usr/bin/env bash
# global-status.sh — Summarize all registered claude-multiagent projects.
#
# Reads ~/.cc/projects.json and prints, for each project:
#   - tmux session status (running / stopped)
#   - number of pending messages in metadata/messages/human/
#   - project status from the registry
#
# Usage:
#   global-status.sh           # human-readable table
#   global-status.sh --json    # JSON output
#   global-status.sh --inbox   # dump full contents of all human inbox messages
#
# This script is automatically installed to ~/.cc/global-status.sh by
# new-project.sh, giving you a single system-level copy to run from anywhere.
#
# Prerequisites: jq, tmux.
set -euo pipefail

CC_DIR="${CC_DIR:-$HOME/.cc}"
REGISTRY="$CC_DIR/projects.json"

if [[ ! -f "$REGISTRY" ]]; then
  echo "No projects registered yet."
  echo "Run new-project.sh to create a project — it registers automatically."
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)" >&2
  exit 1
fi

MODE="table"
case "${1:-}" in
  --json)  MODE="json"  ;;
  --inbox) MODE="inbox" ;;
  --help|-h)
    echo "Usage: global-status.sh [--json | --inbox]"
    echo "  (no args)  Print a summary table of all projects"
    echo "  --json     Print JSON array of project state"
    echo "  --inbox    Dump full contents of each project's human inbox"
    exit 0
    ;;
esac

PROJECT_COUNT=$(jq '.projects | length' "$REGISTRY")
if [[ "$PROJECT_COUNT" -eq 0 ]]; then
  echo "No projects registered."
  exit 0
fi

# Collect data for all projects
declare -a NAMES=()
declare -a PATHS=()
declare -a STATUSES=()
declare -a TMUX_STATUSES=()
declare -a INBOX_COUNTS=()

for i in $(seq 0 $((PROJECT_COUNT - 1))); do
  NAME=$(jq -r ".projects[$i].name" "$REGISTRY")
  PATH_=$(jq -r ".projects[$i].path" "$REGISTRY")
  STATUS=$(jq -r ".projects[$i].status" "$REGISTRY")

  if tmux has-session -t "$NAME" 2>/dev/null; then
    TMUX_STATUS="running"
  else
    TMUX_STATUS="stopped"
  fi

  INBOX_DIR="$PATH_/metadata/messages/human"
  if [[ -d "$INBOX_DIR" ]]; then
    COUNT=$(find "$INBOX_DIR" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  else
    COUNT=0
  fi

  NAMES+=("$NAME")
  PATHS+=("$PATH_")
  STATUSES+=("$STATUS")
  TMUX_STATUSES+=("$TMUX_STATUS")
  INBOX_COUNTS+=("$COUNT")
done

case "$MODE" in
  table)
    printf "%-24s  %-8s  %-8s  %s\n" "PROJECT" "SESSION" "STATUS" "INBOX"
    printf "%-24s  %-8s  %-8s  %s\n" "-------" "-------" "------" "-----"
    for i in "${!NAMES[@]}"; do
      COUNT="${INBOX_COUNTS[$i]}"
      if [[ "$COUNT" -gt 0 ]]; then
        INBOX_LABEL="${COUNT} message(s) pending"
      else
        INBOX_LABEL="-"
      fi
      printf "%-24s  %-8s  %-8s  %s\n" \
        "${NAMES[$i]}" "${TMUX_STATUSES[$i]}" "${STATUSES[$i]}" "$INBOX_LABEL"
    done
    ;;

  json)
    echo "["
    for i in "${!NAMES[@]}"; do
      COMMA=""
      [[ $i -lt $((${#NAMES[@]} - 1)) ]] && COMMA=","
      printf '  {"name":"%s","path":"%s","status":"%s","session":"%s","inbox":%d}%s\n' \
        "${NAMES[$i]}" "${PATHS[$i]}" "${STATUSES[$i]}" \
        "${TMUX_STATUSES[$i]}" "${INBOX_COUNTS[$i]}" "$COMMA"
    done
    echo "]"
    ;;

  inbox)
    for i in "${!NAMES[@]}"; do
      echo "=== ${NAMES[$i]} (session: ${TMUX_STATUSES[$i]}) ==="
      INBOX_DIR="${PATHS[$i]}/metadata/messages/human"
      COUNT="${INBOX_COUNTS[$i]}"
      if [[ -d "$INBOX_DIR" ]] && [[ "$COUNT" -gt 0 ]]; then
        for f in "$INBOX_DIR"/*.md; do
          echo "--- $(basename "$f") ---"
          cat "$f"
          echo ""
        done
      else
        echo "(no messages)"
      fi
      echo ""
    done
    ;;
esac

#!/usr/bin/env bash
# agent-loop.sh — Generic loop for multi-agent Claude Code sessions.
# Checks inbox for work before launching claude. Sessions are fully
# interactive — the initial prompt jumpstarts the agent, but the
# terminal stays open for additional prompts and permission decisions.
#
# Usage:
#   agent-loop.sh <role> [author-number]
#
# Roles: lead, author, reviewer
# Author number (1-N) required when role is "author".
#
# Pause mechanism:
#   Create metadata/pause-<agent> to open an interactive session without
#   an inbox/trigger requirement (no jumpstart prompt).
#   Optional: write guidance text into the file — it will be displayed.
#   Remove the file to resume normal loop on next cycle.
#
# Trigger mechanism:
#   Create metadata/trigger-<agent> to force an immediate cycle.
#   The file is consumed (deleted) when the cycle starts.
#
# Inbox (directory-based, collision-safe):
#   Each agent's inbox is a directory: metadata/messages/<agent>/
#   Messages are individual .md files written by senders.
#   The agent reads all files in its inbox dir, processes them, and deletes them.
#
# Logs:
#   Loop events are logged to metadata/logs/<agent>.log.
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

ROLE="${1:-}"
AUTHOR_NUM="${2:-}"

if [[ -z "$ROLE" ]]; then
  echo "Usage: agent-loop.sh <role> [author-number]"
  echo "Roles: lead, author, reviewer"
  exit 1
fi

if [[ "$ROLE" == "author" && -z "$AUTHOR_NUM" ]]; then
  echo "Error: author role requires an author number."
  echo "Usage: agent-loop.sh author <N>"
  exit 1
fi

# --- Derive agent name ---
if [[ "$ROLE" == "author" ]]; then
  AGENT_NAME="author-${AUTHOR_NUM}"
else
  AGENT_NAME="$ROLE"
fi

# --- Role configuration ---
case "$ROLE" in
  lead)
    MODEL="sonnet"
    WORKDIR="$WORKSPACE_ROOT/.claude-workspace/lead-agent"
    PROMPT_FILE="$WORKSPACE_ROOT/scripts/prompts/lead.txt"
    POLL_INTERVAL=60
    ;;
  author)
    MODEL="sonnet"
    WORKDIR="$WORKSPACE_ROOT/.claude-workspace/author-template"
    PROMPT_FILE="$WORKSPACE_ROOT/scripts/prompts/author.txt"
    # Stagger poll intervals to avoid thundering herd on the Beads database.
    # Author 1: 30s, Author 2: 47s, Author 3: 64s — they never poll at the same time.
    POLL_INTERVAL=$((30 + (AUTHOR_NUM - 1) * 17))
    ;;
  reviewer)
    MODEL="opus"
    WORKDIR="$WORKSPACE_ROOT/.claude-workspace/reviewer"
    PROMPT_FILE="$WORKSPACE_ROOT/scripts/prompts/reviewer.txt"
    POLL_INTERVAL=30
    ;;
  *)
    echo "Error: unknown role '$ROLE'. Must be lead, author, or reviewer." >&2
    exit 1
    ;;
esac

# --- Paths ---
INBOX_DIR="$WORKSPACE_ROOT/metadata/messages/${AGENT_NAME}"
PAUSE_FILE="$WORKSPACE_ROOT/metadata/pause-${AGENT_NAME}"
TRIGGER_FILE="$WORKSPACE_ROOT/metadata/trigger-${AGENT_NAME}"
LOG_DIR="$WORKSPACE_ROOT/metadata/logs"
LOG_FILE="$LOG_DIR/${AGENT_NAME}.log"
mkdir -p "$LOG_DIR"
mkdir -p "$INBOX_DIR"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

# --- Build prompt (substitute placeholders) ---
build_prompt() {
  local prompt
  prompt=$(<"$PROMPT_FILE")
  if [[ "$ROLE" == "author" ]]; then
    prompt="${prompt//\$AUTHOR_NUM/$AUTHOR_NUM}"
  fi
  prompt="${prompt//\$DATE/$(date +%Y-%m-%d)}"
  echo "$prompt"
}

# --- Check if inbox directory has any messages ---
inbox_has_work() {
  [[ -d "$INBOX_DIR" ]] && compgen -G "$INBOX_DIR/*.md" > /dev/null 2>&1
}

# --- Check if Beads queue has open tasks (authors only) ---
queue_has_work() {
  bd ready 2>/dev/null | grep -q 'beads-central-'
}

# --- Log helper ---
log() {
  echo "$@" | tee -a "$LOG_FILE"
}

# --- Loop state ---
CONSECUTIVE_FAILURES=0
MAX_FAILURES=5
RESTART_DELAY=5
CYCLE=0
# Adaptive idle backoff — starts at POLL_INTERVAL, doubles up to MAX_POLL_DELAY.
# Zero LLM sessions launched for idle polling; Claude only wakes when there is work.
IDLE_POLL_DELAY=$POLL_INTERVAL
MAX_POLL_DELAY=300

FIRST_RUN=false
if [[ "$ROLE" == "lead" ]]; then
  FIRST_RUN=true
fi

log "=== agent-loop.sh: agent=$AGENT_NAME model=$MODEL (interactive) ==="
log "=== Working directory: $WORKDIR ==="
log "=== Inbox: $INBOX_DIR/ ==="
log "=== Log file: $LOG_FILE ==="
log "=== Pause file: $PAUSE_FILE ==="
log "=== Trigger file: $TRIGGER_FILE ==="
log "=== Poll interval: ${POLL_INTERVAL}s initial (adaptive backoff up to 300s) ==="
log ""

cd "$WORKDIR"

while true; do

  # --- Check for pause file ---
  if [[ -f "$PAUSE_FILE" ]]; then
    log ""
    log "========================================"
    log "  PAUSED — interactive mode"
    log "========================================"
    if [[ -s "$PAUSE_FILE" ]]; then
      log ""
      log "Guidance from pause file:"
      log "$(cat "$PAUSE_FILE")"
      log ""
    fi
    log "Launching claude (model=$MODEL) in $WORKDIR (no jumpstart prompt)"
    log "Remove $PAUSE_FILE to resume normal loop after this session."
    log "========================================"
    log ""
    EXIT_CODE=0
    claude --model "$MODEL" || EXIT_CODE=$?
    log "--- Interactive session ended (exit $EXIT_CODE) at $(date '+%Y-%m-%d %H:%M:%S') ---"
    if [[ -f "$PAUSE_FILE" ]]; then
      log "Pause file still exists. Will open another session after delay."
    else
      log "Pause file removed. Resuming normal loop."
      CONSECUTIVE_FAILURES=0
    fi
    sleep "$RESTART_DELAY"
    continue
  fi

  # --- Determine if there's work to do ---
  LAUNCH_REASON=""

  if [[ "$FIRST_RUN" == "true" ]]; then
    FIRST_RUN=false
    LAUNCH_REASON="first-run"
  elif [[ -f "$TRIGGER_FILE" ]]; then
    rm -f "$TRIGGER_FILE"
    LAUNCH_REASON="trigger"
  elif inbox_has_work; then
    LAUNCH_REASON="inbox"
  elif [[ "$ROLE" == "author" ]] && queue_has_work; then
    LAUNCH_REASON="queue"
  fi

  if [[ -z "$LAUNCH_REASON" ]]; then
    echo "[$(date '+%H:%M:%S')] No work (inbox empty, queue empty). Polling in ${IDLE_POLL_DELAY}s..."
    sleep "$IDLE_POLL_DELAY"
    # Adaptive backoff: double the interval up to MAX_POLL_DELAY (zero LLM cost)
    IDLE_POLL_DELAY=$(( IDLE_POLL_DELAY * 2 > MAX_POLL_DELAY ? MAX_POLL_DELAY : IDLE_POLL_DELAY * 2 ))
    continue
  fi

  # Reset idle backoff when work is found
  IDLE_POLL_DELAY=$POLL_INTERVAL

  # --- Launch claude ---
  CYCLE=$((CYCLE + 1))
  log "--- Cycle $CYCLE starting at $(date '+%Y-%m-%d %H:%M:%S') (trigger: $LAUNCH_REASON) ---"

  PROMPT=$(build_prompt)
  EXIT_CODE=0
  claude --model "$MODEL" "$PROMPT" || EXIT_CODE=$?

  log ""
  log "--- Cycle $CYCLE ended at $(date '+%Y-%m-%d %H:%M:%S') with exit code $EXIT_CODE ---"

  if [[ $EXIT_CODE -eq 0 ]]; then
    CONSECUTIVE_FAILURES=0
    log "Session closed. Checking for new work after ${RESTART_DELAY}s."
  else
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    log "Cycle failed (exit $EXIT_CODE). Consecutive failures: $CONSECUTIVE_FAILURES/$MAX_FAILURES."
    if [[ $CONSECUTIVE_FAILURES -ge $MAX_FAILURES ]]; then
      log "ERROR: $MAX_FAILURES consecutive failures. Stopping agent loop."
      exit 1
    fi
    BACKOFF=$((RESTART_DELAY * (2 ** (CONSECUTIVE_FAILURES - 1))))
    log "Backing off for ${BACKOFF}s before retry."
    sleep "$BACKOFF"
    continue
  fi

  sleep "$RESTART_DELAY"
done

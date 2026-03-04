#!/usr/bin/env bash
# Launch the multi-agent tmux session.
# Session name matches the project name.
# Prerequisites: tmux, Claude Code CLI (claude), beads (bd).
#
# Command center (run separately, outside tmux):
#   cd $WORKSPACE_ROOT/.claude-workspace/command-center && claude
#
# Example:
#   ~/projects/[[PROJECT_NAME]]/launch-agents.sh
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
# shellcheck source=scripts/env.sh
source "$WORKSPACE_ROOT/scripts/env.sh"
SESSION="[[PROJECT_NAME]]"
LOOP="$WORKSPACE_ROOT/scripts/agent-loop.sh"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already exists. Attach with: tmux attach -t $SESSION"
  exit 0
fi

# ── Workspace isolation check ─────────────────────────────────────────────────
# Catch cross-project contamination before any agent reads a poisoned file.
ISOLATION_CHECK="$WORKSPACE_ROOT/scripts/check-workspace-isolation.sh"
if [[ -f "$ISOLATION_CHECK" ]]; then
  if ! "$ISOLATION_CHECK" "$WORKSPACE_ROOT" 2>&1; then
    echo ""
    echo "ERROR: Workspace isolation check failed. Agents NOT started." >&2
    echo "Fix the cross-project references shown above, then re-run launch-agents.sh." >&2
    exit 1
  fi
fi

# Clear stale Beads lock files from any previous crashed agents.
# Safe here because no tmux session (and therefore no bd process) is running.
BEADS_DB="${BEADS_DIR:-$WORKSPACE_ROOT/beads-central/.beads}"
rm -f "$BEADS_DB/dolt-access.lock"
# Derive the Dolt database name from metadata.json so this path stays correct
# if the database was named differently at init time (avoids hardcoding).
DOLT_DB_NAME="$(jq -r '.dolt_database // empty' "$BEADS_DB/metadata.json" 2>/dev/null || true)"
if [[ -n "$DOLT_DB_NAME" ]]; then
  rm -f "$BEADS_DB/dolt/$DOLT_DB_NAME/.dolt/noms/LOCK"
fi

# Start Beads dolt SQL server (server mode — required for concurrent agent access).
# Skip start if server is already running; start it otherwise.
if bd dolt test > /dev/null 2>&1; then
  echo "Dolt server already running — skipping start."
else
  bd dolt start || echo "Warning: bd dolt start failed — check $BEADS_DB/dolt-server.log"
fi

# Clean up stale temp files from previous sessions
if [[ -f "$WORKSPACE_ROOT/scripts/tmp-clean.sh" ]]; then
  "$WORKSPACE_ROOT/scripts/tmp-clean.sh" --all --older-than 1 --quiet || true
fi

# Sweep stale worktrees for completed features
if [[ -f "$WORKSPACE_ROOT/scripts/sweep-stale-worktrees.sh" ]]; then
  "$WORKSPACE_ROOT/scripts/sweep-stale-worktrees.sh" --quiet || true
fi

# Prune old archived inbox messages
if [[ -f "$WORKSPACE_ROOT/scripts/prune-message-archive.sh" ]]; then
  "$WORKSPACE_ROOT/scripts/prune-message-archive.sh" --agent-days 7 --human-days 14 --quiet || true
fi

# Clear nested-session guard so Claude Code can launch inside tmux panes
tmux new-session -d -s "$SESSION" -c "$WORKSPACE_ROOT" -e CLAUDECODE=""
tmux rename-window -t "$SESSION" "agents"
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{@pane_label} "

# Total panes: Lead + NUM_AUTHORS + Reviewer + spare = NUM_AUTHORS + 3
# Additional splits beyond the initial pane 0: NUM_AUTHORS + 2
NUM_EXTRA=$((NUM_AUTHORS + 2))
for i in $(seq 1 "$NUM_EXTRA"); do
  tmux split-window -t "$SESSION" -c "$WORKSPACE_ROOT" -e CLAUDECODE=""
  tmux select-layout -t "$SESSION" tiled
done

# Pane 0: Lead
tmux send-keys -t "${SESSION}:agents.0" "source $WORKSPACE_ROOT/scripts/env.sh && $LOOP lead" C-m
tmux set-option -pt "${SESSION}:agents.0" @pane_label "lead"

# Panes 1..NUM_AUTHORS: Authors
for i in $(seq 1 "$NUM_AUTHORS"); do
  tmux send-keys -t "${SESSION}:agents.$i" "source $WORKSPACE_ROOT/scripts/env.sh && $LOOP author $i" C-m
  tmux set-option -pt "${SESSION}:agents.$i" @pane_label "author-$i"
done

# Pane NUM_AUTHORS+1: Reviewer
REVIEWER_PANE=$((NUM_AUTHORS + 1))
tmux send-keys -t "${SESSION}:agents.$REVIEWER_PANE" "source $WORKSPACE_ROOT/scripts/env.sh && $LOOP reviewer" C-m
tmux set-option -pt "${SESSION}:agents.$REVIEWER_PANE" @pane_label "reviewer"

# Pane NUM_AUTHORS+2: spare
SPARE_PANE=$((NUM_AUTHORS + 2))
tmux send-keys -t "${SESSION}:agents.$SPARE_PANE" "echo 'Spare pane — use for ad-hoc commands'" C-m
tmux set-option -pt "${SESSION}:agents.$SPARE_PANE" @pane_label "spare"

tmux select-pane -t "${SESSION}:agents.0"

echo "Session '$SESSION' started. Attach with: tmux attach -t $SESSION"

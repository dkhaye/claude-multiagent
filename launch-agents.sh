#!/usr/bin/env bash
# Launch the multi-agent tmux session.
# Session name matches the project name.
# Prerequisites: tmux, Claude Code CLI (claude), beads (bd).
#
# Command center (run separately, outside tmux):
#   cd $WORKSPACE_ROOT/.claude-workspace/command-center && claude
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"
SESSION="[[PROJECT_NAME]]"
LOOP="$WORKSPACE_ROOT/scripts/agent-loop.sh"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already exists. Attach with: tmux attach -t $SESSION"
  exit 0
fi

# Clear stale Beads lock files from any previous crashed agents.
# Safe here because no tmux session (and therefore no bd process) is running.
BEADS_DB="${BEADS_DIR:-$WORKSPACE_ROOT/beads-central/.beads}"
rm -f "$BEADS_DB/dolt-access.lock"
rm -f "$BEADS_DB/dolt/beads_beads-central/.dolt/noms/LOCK"

# Clean up stale temp files from previous sessions
if [[ -f "$WORKSPACE_ROOT/scripts/tmp-clean.sh" ]]; then
  "$WORKSPACE_ROOT/scripts/tmp-clean.sh" --beads --older-than 1 --quiet || true
fi

# Clear nested-session guard so Claude Code can launch inside tmux panes
tmux new-session -d -s "$SESSION" -c "$WORKSPACE_ROOT" -e CLAUDECODE=""
tmux rename-window -t "$SESSION" "agents"

# Total panes: Lead + NUM_AUTHORS + Reviewer + spare = NUM_AUTHORS + 3
# Additional splits beyond the initial pane 0: NUM_AUTHORS + 2
NUM_EXTRA=$((NUM_AUTHORS + 2))
for i in $(seq 1 "$NUM_EXTRA"); do
  tmux split-window -t "$SESSION" -c "$WORKSPACE_ROOT"
  tmux select-layout -t "$SESSION" tiled
done

# Pane 0: Lead
tmux send-keys -t "${SESSION}:agents.0" "source $WORKSPACE_ROOT/scripts/env.sh && $LOOP lead" C-m

# Panes 1..NUM_AUTHORS: Authors
for i in $(seq 1 "$NUM_AUTHORS"); do
  tmux send-keys -t "${SESSION}:agents.$i" "source $WORKSPACE_ROOT/scripts/env.sh && $LOOP author $i" C-m
done

# Pane NUM_AUTHORS+1: Reviewer
REVIEWER_PANE=$((NUM_AUTHORS + 1))
tmux send-keys -t "${SESSION}:agents.$REVIEWER_PANE" "source $WORKSPACE_ROOT/scripts/env.sh && $LOOP reviewer" C-m

# Pane NUM_AUTHORS+2: spare
SPARE_PANE=$((NUM_AUTHORS + 2))
tmux send-keys -t "${SESSION}:agents.$SPARE_PANE" "echo 'Spare pane — use for ad-hoc commands'" C-m

tmux select-pane -t "${SESSION}:agents.0"

echo "Session '$SESSION' started. Attach with: tmux attach -t $SESSION"

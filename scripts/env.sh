# Multi-agent workspace environment: PATH and tool lookup.
# Source this before running commands that need tmux, beads, claude, etc.
# Usage: source scripts/env.sh   (or: . scripts/env.sh)

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
SCRIPT_DIR="${SCRIPT_DIR:-$WORKSPACE_ROOT/scripts}"
NUM_AUTHORS="${NUM_AUTHORS:-[[NUM_AUTHORS]]}"

# Homebrew (tmux, beads, and other brew-installed tools)
BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}"
export PATH="$BREW_PREFIX/bin:$PATH"

# Claude Code CLI
export PATH="$HOME/.local/bin:$PATH"

# Optional: prepend project scripts for convenience
export PATH="$SCRIPT_DIR:$PATH"

export WORKSPACE_ROOT

# Beads: all bd commands use beads-central as the single coordination database
export BEADS_DIR="$WORKSPACE_ROOT/beads-central/.beads"

export CLAUDE_MULTIAGENT_ENV_LOADED=1

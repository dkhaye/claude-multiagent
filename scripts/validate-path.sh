#!/usr/bin/env bash
# Validate that a path is under the workspace and is a known repo or worktree.
# Usage: ./validate-path.sh <path>
# Exit 0 if valid, 1 otherwise.
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
REPOS_ROOT="$WORKSPACE_ROOT/repos"
WORKTREES_ROOT="$WORKSPACE_ROOT/worktrees"

PATH_ARG="${1:?Usage: $0 <path>}"
ABS="$(cd "$PATH_ARG" 2>/dev/null && pwd -P)" || true

if [[ -z "${ABS:-}" ]]; then
  echo "Invalid or missing path: $PATH_ARG" >&2
  exit 1
fi

if [[ "$ABS" != "$WORKSPACE_ROOT"* ]]; then
  echo "Path not under workspace: $ABS" >&2
  exit 1
fi

if [[ -d "$ABS/.git" ]]; then
  echo "Valid repo/worktree: $ABS"
  exit 0
fi

echo "Not a git repo: $ABS" >&2
exit 1

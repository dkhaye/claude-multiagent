#!/usr/bin/env bash
# Run a node binary in a project directory using NVM-managed node.
# Loads NVM, activates the .nvmrc version from the project dir if present,
# then execs the given command.
#
# Usage: node-exec.sh <project-dir> <command> [args...]
#
# Examples:
#   $WORKSPACE_ROOT/scripts/node-exec.sh /worktree/path/pkg publint .
#   $WORKSPACE_ROOT/scripts/node-exec.sh /worktree/path/pkg \
#       /worktree/path/node_modules/.bin/publint .
#   $WORKSPACE_ROOT/scripts/node-exec.sh /worktree/path node --version
set -euo pipefail

dir="${1:?Usage: $0 <project-dir> <command> [args...]}"
shift

# Load NVM without auto-activating any version.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" --no-use

cd "$dir"

# Activate the .nvmrc version if one exists.
[ -f ".nvmrc" ] && nvm use --silent

exec "$@"

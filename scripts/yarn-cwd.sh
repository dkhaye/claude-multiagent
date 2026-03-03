#!/usr/bin/env bash
# Run yarn in a specific directory via corepack.
# Corepack resolves packageManager from CWD, so we must cd first.
# Also loads NVM and activates the project's .nvmrc node version if present.
# Usage: yarn-cwd.sh <project-dir> [yarn-args...]
set -euo pipefail

dir="${1:?Usage: $0 <project-dir> [yarn-args...]}"
shift

# Load NVM without auto-activating any version.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" --no-use

cd "$dir"

# Activate the .nvmrc version if one exists.
[ -f ".nvmrc" ] && nvm use --silent

exec corepack yarn "$@"

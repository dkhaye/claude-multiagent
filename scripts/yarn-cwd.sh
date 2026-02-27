#!/usr/bin/env bash
# Run yarn in a specific directory via corepack.
# Corepack resolves packageManager from CWD, so we must cd first.
# Usage: yarn-cwd.sh <project-dir> [yarn-args...]
set -euo pipefail

dir="${1:?Usage: $0 <project-dir> [yarn-args...]}"
shift
cd "$dir"
exec corepack yarn "$@"

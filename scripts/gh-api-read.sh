#!/usr/bin/env bash
# gh-api-read.sh — Read-only GitHub API wrapper for agents.
# Enforces --method GET so agents cannot make mutating API calls through this script.
# Also handles base64 file decoding to avoid pipes.
#
# Usage:
#   gh-api-read.sh <endpoint> [gh api flags...]
#   gh-api-read.sh <endpoint> --decode-content  # base64-decode the .content field (file reads)
#
# Examples:
#   gh-api-read.sh repos/OWNER/REPO/contents/.github/workflows --jq '.[].name'
#   gh-api-read.sh repos/OWNER/REPO/contents/.github/workflows/build.yml --decode-content
#   gh-api-read.sh repos/OWNER/REPO/git/ref/heads/main
#   gh-api-read.sh repos/OWNER/REPO/actions/runs --jq '.workflow_runs[0].status'
set -euo pipefail

ENDPOINT="${1:?Usage: gh-api-read.sh <endpoint> [gh api flags...]}"
shift

DECODE_CONTENT=false
PASSTHROUGH=()
for arg in "$@"; do
  if [[ "$arg" == "--decode-content" ]]; then
    DECODE_CONTENT=true
  else
    PASSTHROUGH+=("$arg")
  fi
done

if [[ "$DECODE_CONTENT" == "true" ]]; then
  gh api --method GET "$ENDPOINT" "${PASSTHROUGH[@]}" --jq '.content' | base64 --decode
else
  gh api --method GET "$ENDPOINT" "${PASSTHROUGH[@]}"
fi

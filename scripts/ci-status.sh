#!/usr/bin/env bash
# ci-status.sh — Show CI check status for all open PRs in metadata/open-prs.json.
#
# Usage:
#   ci-status.sh                # Show all PRs with their check results
#   ci-status.sh --fail-only    # Show only PRs with failing checks
#   ci-status.sh --summary      # One line per PR (pass/fail count only, no per-check detail)
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

PRS_FILE="$WORKSPACE_ROOT/metadata/open-prs.json"
FAIL_ONLY=false
SUMMARY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fail-only) FAIL_ONLY=true; shift ;;
    --summary)   SUMMARY=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$PRS_FILE" ]]; then
  echo "No open-prs.json found at $PRS_FILE"
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)" >&2
  exit 1
fi

PR_COUNT=$(jq '.open_prs | length' "$PRS_FILE")
if [[ "$PR_COUNT" -eq 0 ]]; then
  echo "No open PRs tracked in $PRS_FILE"
  exit 0
fi

echo ""
FAILED_PRS=0

for i in $(seq 0 $((PR_COUNT - 1))); do
  NUMBER=$(jq -r ".open_prs[$i].number" "$PRS_FILE")
  REPO=$(jq -r   ".open_prs[$i].repo"   "$PRS_FILE")
  TITLE=$(jq -r  ".open_prs[$i].title"  "$PRS_FILE")
  AUTHOR=$(jq -r ".open_prs[$i].author" "$PRS_FILE")
  URL=$(jq -r    ".open_prs[$i].url"    "$PRS_FILE")

  # Run gh pr checks — capture output and exit code
  CHECKS_OUT=""
  CHECKS_OK=true
  CHECKS_OUT=$(gh pr checks "$NUMBER" --repo "$REPO" 2>&1) || CHECKS_OK=false

  # Detect failures: lines containing "fail" (case-insensitive)
  HAS_FAILURE=false
  if ! $CHECKS_OK || echo "$CHECKS_OUT" | grep -qi "fail\|error"; then
    HAS_FAILURE=true
    FAILED_PRS=$((FAILED_PRS + 1))
  fi

  $FAIL_ONLY && ! $HAS_FAILURE && continue

  echo "=== PR #${NUMBER} — ${TITLE} ==="
  echo "    Repo:   $REPO"
  echo "    Author: $AUTHOR"
  echo "    URL:    $URL"

  if $SUMMARY; then
    PASS_COUNT=$(echo "$CHECKS_OUT" | grep -ci "pass\|success" || true)
    FAIL_COUNT=$(echo "$CHECKS_OUT" | grep -ci "fail\|error"   || true)
    echo "    Checks: ${PASS_COUNT} passing, ${FAIL_COUNT} failing"
  else
    echo ""
    echo "$CHECKS_OUT" | sed 's/^/    /'
  fi
  echo ""
done

if [[ "$FAILED_PRS" -gt 0 ]]; then
  echo ">>> $FAILED_PRS open PR(s) have failing checks <<<"
  exit 1
else
  echo "All ${PR_COUNT} open PR(s) are passing."
fi

#!/usr/bin/env bash
# pr-changed-since-review.sh — Check whether a PR has new commits since its last review.
#
# Fetches the PR's review and commit history and compares the most recent
# review submission timestamp against the most recent commit timestamp.
#
# Usage:
#   pr-changed-since-review.sh <pr-number> <owner/repo>
#
# Output (one line to stdout):
#   CHANGED <latest-commit-sha>           — new commits exist since last review
#   UNCHANGED (reviewed: <ISO-date>)      — no new commits since last review; skip
#   NO_REVIEW                             — no reviews yet; proceed with full review
#
# Reviewer uses this as the first step of every review cycle to avoid re-reviewing
# unchanged PRs and to detect when code was pushed after a request-changes review.
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

NUMBER="${1:-}"
REPO="${2:-}"

if [[ -z "$NUMBER" || -z "$REPO" ]]; then
  echo "Usage: pr-changed-since-review.sh <pr-number> <owner/repo>" >&2
  echo "  e.g. pr-changed-since-review.sh 50 org/repo-name" >&2
  exit 1
fi

PR_JSON=$(gh pr view "$NUMBER" --repo "$REPO" --json reviews,commits 2>/dev/null)

REVIEW_COUNT=$(echo "$PR_JSON" | jq '.reviews | length')
if [[ "$REVIEW_COUNT" -eq 0 ]]; then
  echo "NO_REVIEW"
  exit 0
fi

# Most recent review submission timestamp (ISO 8601)
LAST_REVIEW_DATE=$(echo "$PR_JSON" | jq -r \
  '.reviews | sort_by(.submittedAt) | last | .submittedAt')

# Most recent commit (by committedDate)
LATEST_COMMIT_DATE=$(echo "$PR_JSON" | jq -r \
  '.commits | sort_by(.committedDate) | last | .committedDate')
LATEST_COMMIT_SHA=$(echo "$PR_JSON" | jq -r \
  '.commits | sort_by(.committedDate) | last | .oid')

# ISO 8601 dates sort correctly as strings (lexicographic = chronological)
if [[ "$LATEST_COMMIT_DATE" > "$LAST_REVIEW_DATE" ]]; then
  echo "CHANGED ${LATEST_COMMIT_SHA:0:8}"
else
  echo "UNCHANGED (reviewed: $LAST_REVIEW_DATE)"
fi

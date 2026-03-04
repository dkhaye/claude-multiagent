#!/usr/bin/env bash
# pr-create.sh — Create a GitHub PR and register it in metadata/open-prs.json.
#
# A thin wrapper around `gh pr create` that adds registry tracking.
# All flags except --cc-author and --cc-feature are forwarded to gh.
#
# Usage:
#   pr-create.sh --repo <org/repo> --title <title> --body-file <file> \
#                [--head <branch>] [--base <branch>] [--draft]         \
#                [--cc-author <agent-name>]                             \
#                [--cc-feature <feature-name>]
#
# --cc-author and --cc-feature are registry metadata only — not passed to gh.
# All other flags are forwarded to `gh pr create` as-is.
#
# Prints the new PR URL to stdout (same as gh pr create).
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

CC_AUTHOR="unknown"
CC_FEATURE=""
GH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cc-author)  CC_AUTHOR="$2";  shift 2 ;;
    --cc-feature) CC_FEATURE="$2"; shift 2 ;;
    *)            GH_ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#GH_ARGS[@]} -eq 0 ]]; then
  echo "Usage: pr-create.sh --repo <org/repo> --title <title> --body-file <file> [gh flags]" >&2
  echo "       [--cc-author <agent>] [--cc-feature <feature>]" >&2
  exit 1
fi

# Create the PR — gh prints the URL on success
PR_URL=$(gh pr create "${GH_ARGS[@]}")
echo "$PR_URL"

# Extract PR number from URL (last path segment)
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

# Extract --repo and --title values from the forwarded args for registry
REPO=""
TITLE=""
prev=""
for arg in "${GH_ARGS[@]}"; do
  case "$prev" in
    --repo)  REPO="$arg"  ;;
    --title) TITLE="$arg" ;;
  esac
  prev="$arg"
done

# Register in metadata/open-prs.json
PRS_FILE="$WORKSPACE_ROOT/metadata/open-prs.json"
if command -v jq &>/dev/null; then
  # Initialize schema v2 file if missing
  if [[ ! -f "$PRS_FILE" ]]; then
    printf '{"schema_version":2,"open_prs":[],"merged_recently":[]}\n' > "$PRS_FILE"
  fi
  ENTRY=$(jq -n \
    --argjson number "$PR_NUMBER" \
    --arg     repo    "$REPO"      \
    --arg     url     "$PR_URL"    \
    --arg     title   "$TITLE"     \
    --arg     author  "$CC_AUTHOR" \
    --arg     feature "$CC_FEATURE" \
    --arg     opened  "$(date +%Y-%m-%d)" \
    '{number: $number, repo: $repo, url: $url, title: $title,
      author: $author, feature: $feature, opened: $opened,
      status: "ci_unknown", human_approved: false}')
  tmp="$(mktemp)"
  jq --argjson entry "$ENTRY" '.open_prs += [$entry]' "$PRS_FILE" > "$tmp"
  mv "$tmp" "$PRS_FILE"
  echo "Registered PR #${PR_NUMBER} in open-prs.json" >&2
fi

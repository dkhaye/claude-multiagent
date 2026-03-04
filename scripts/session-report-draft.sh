#!/usr/bin/env bash
# session-report-draft.sh — Generate a draft Slack session report skeleton.
#
# Reads metadata/open-prs.json and classifies each PR into the approved 5-bucket
# format. Lead fills in the Blockers section and adds one-line descriptions to
# Ready-to-merge entries, then posts to Slack via post-to-slack.sh.
#
# Bucket classification:
#   Ready to merge      — ci_green + human_approved:true + LGTM in notes
#   Awaiting >24h       — ci_green + human_approved:false + LGTM + opened >24h ago
#   Awaiting <24h       — ci_green + human_approved:false + LGTM + opened <=24h ago
#   Other PRs           — everything else
#   (Blockers section is a placeholder — Lead fills in manually)
#
# PR age is determined by calling gh pr view when needed (only for LGTM PRs).
#
# Usage:
#   session-report-draft.sh              # Print draft to stdout
#   session-report-draft.sh --out <file> # Write draft to file (for posting to Slack)
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
source "$WORKSPACE_ROOT/scripts/env.sh"

PRS_FILE="$WORKSPACE_ROOT/metadata/open-prs.json"
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)    OUT_FILE="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: session-report-draft.sh [--out <file>]"
      echo "  --out <file>  Write draft to file instead of stdout"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$PRS_FILE" ]]; then
  echo "No open-prs.json found at $PRS_FILE" >&2
  exit 1
fi

NOW_EPOCH=$(date +%s)

pr_link() {
  local repo="$1" number="$2"
  echo "[${repo}#${number}](https://github.com/${repo}/pull/${number})"
}

pr_age_hours() {
  local repo="$1" number="$2"
  local created
  created=$(gh pr view "$number" --repo "$repo" --json createdAt \
    --jq '.createdAt' 2>/dev/null || echo "")
  if [[ -z "$created" ]]; then echo "0"; return; fi

  local created_epoch
  # macOS date
  created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created" +%s 2>/dev/null) || \
  # GNU date (Linux fallback)
  created_epoch=$(date -d "$created" +%s 2>/dev/null) || \
  created_epoch=0

  echo $(( (NOW_EPOCH - created_epoch) / 3600 ))
}

has_lgtm() {
  local notes="$1"
  echo "$notes" | grep -qiE '\bLGTM\b' && echo "true" || echo "false"
}

READY=()
WAITING_LONG=()
WAITING_SHORT=()
OTHER=()

PR_COUNT=$(jq '.open_prs | length' "$PRS_FILE")

for i in $(seq 0 $((PR_COUNT - 1))); do
  REPO=$(jq -r          ".open_prs[$i].repo"            "$PRS_FILE")
  NUMBER=$(jq -r        ".open_prs[$i].number"           "$PRS_FILE")
  STATUS=$(jq -r        ".open_prs[$i].status"           "$PRS_FILE")
  NOTES=$(jq -r         ".open_prs[$i].notes // \"\""   "$PRS_FILE")
  HUMAN_APPROVED=$(jq -r ".open_prs[$i].human_approved // false" "$PRS_FILE")

  LINK=$(pr_link "$REPO" "$NUMBER")
  LGTM=$(has_lgtm "$NOTES")

  if [[ "$STATUS" == "ci_green" && "$LGTM" == "true" && "$HUMAN_APPROVED" == "true" ]]; then
    READY+=("$LINK")
  elif [[ "$STATUS" == "ci_green" && "$LGTM" == "true" && "$HUMAN_APPROVED" == "false" ]]; then
    AGE=$(pr_age_hours "$REPO" "$NUMBER")
    if [[ "$AGE" -ge 24 ]]; then
      WAITING_LONG+=("$LINK")
    else
      WAITING_SHORT+=("$LINK")
    fi
  else
    OTHER+=("$LINK")
  fi
done

generate_report() {
  echo "## Blockers"
  echo ""
  echo "<!-- TODO: fill in blockers manually — terraform applies, EIP limits, prerequisite merges -->"
  echo ""

  if [[ ${#READY[@]} -gt 0 ]]; then
    echo "## Ready to merge"
    echo ""
    for link in "${READY[@]}"; do
      echo "${link} — <!-- add one-line description -->"
    done
    echo ""
  fi

  if [[ ${#WAITING_LONG[@]} -gt 0 ]]; then
    echo "## Awaiting external approval (>24h)"
    echo ""
    echo "${WAITING_LONG[*]}"
    echo ""
  fi

  if [[ ${#WAITING_SHORT[@]} -gt 0 ]]; then
    echo "## Awaiting external approval (<24h)"
    echo ""
    echo "${WAITING_SHORT[*]}"
    echo ""
  fi

  if [[ ${#OTHER[@]} -gt 0 ]]; then
    echo "## Other PRs"
    echo ""
    echo "${OTHER[*]}"
    echo ""
  fi
}

if [[ -n "$OUT_FILE" ]]; then
  generate_report > "$OUT_FILE"
  echo "Draft written to ${OUT_FILE}" >&2
  echo "Next: fill in Blockers section, add descriptions to Ready-to-merge entries," >&2
  echo "      then: ~/projects/[[PROJECT_NAME]]/scripts/post-to-slack.sh ${OUT_FILE}" >&2
else
  generate_report
fi

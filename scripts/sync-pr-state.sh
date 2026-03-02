#!/usr/bin/env bash
# sync-pr-state.sh
# Reconciles metadata/open-prs.json against actual GitHub PR state.
# Moves merged/closed PRs from open_prs into merged_recently.
# Prints a compact change summary — the JSON file is updated in-place.
#
# Usage:
#   sync-pr-state.sh          # merge-state check only (fast: 1 API call/PR)
#   sync-pr-state.sh --ci     # also refresh CI status (2 API calls/PR)
#
# Run as Step 0 at the start of every lead session.
# The LLM reads ONLY the printed summary, not the full JSON — keep output brief.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_FILE="$SCRIPT_DIR/../metadata/open-prs.json"
REFRESH_CI=false
[[ "${1:-}" == "--ci" ]] && REFRESH_CI=true

# ── temp files (cleaned up on exit) ──────────────────────────────────────────
MERGED_TMP=$(mktemp)   # repo|number|date
CLOSED_TMP=$(mktemp)   # repo|number
CI_TMP=$(mktemp)       # repo|number|new_status  (--ci only)
trap 'rm -f "$MERGED_TMP" "$CLOSED_TMP" "$CI_TMP"' EXIT

TODAY=$(date -u +%Y-%m-%d)
open_count=$(jq '.open_prs | length' "$PR_FILE")
printf 'sync-pr-state: checking %d open PRs...\n' "$open_count"

# ── collect current open PR pairs (bash 3 compatible) ────────────────────────
PR_PAIRS=()
while IFS= read -r line; do
    PR_PAIRS+=("$line")
done < <(jq -r '.open_prs[] | "\(.repo)|\(.number)"' "$PR_FILE")

n_unchanged=0
for pair in "${PR_PAIRS[@]}"; do
    repo="${pair%%|*}"
    num="${pair##*|}"

    # Single gh call: state + mergedAt
    pr_data=$(gh pr view "$num" --repo "$repo" \
        --json state,mergedAt 2>/dev/null \
        || printf '{"state":"UNKNOWN","mergedAt":null}')

    state=$(printf '%s\n' "$pr_data" | jq -r '.state')

    case "$state" in
        MERGED)
            merged_at=$(printf '%s\n' "$pr_data" | jq -r '(.mergedAt // "") | .[0:10]')
            printf '%s|%s|%s\n' "$repo" "$num" "${merged_at:-$TODAY}" >> "$MERGED_TMP"
            printf '  MERGED  %s#%s  (%s)\n' "$repo" "$num" "${merged_at:-$TODAY}"
            ;;
        CLOSED)
            printf '%s|%s\n' "$repo" "$num" >> "$CLOSED_TMP"
            printf '  CLOSED  %s#%s  (not merged)\n' "$repo" "$num"
            ;;
        *)
            n_unchanged=$((n_unchanged + 1))

            if [[ "$REFRESH_CI" == "true" ]]; then
                ci_data=$(gh pr view "$num" --repo "$repo" \
                    --json statusCheckRollup 2>/dev/null \
                    || printf '{"statusCheckRollup":[]}')

                # Classify in jq — avoids fragile text parsing
                new_status=$(printf '%s\n' "$ci_data" | jq -r '
                    (.statusCheckRollup // []) as $c |
                    if ($c | length) == 0 then "ci_unknown"
                    elif ($c | map(select(
                            .conclusion == "FAILURE" or
                            .conclusion == "ACTION_REQUIRED" or
                            .conclusion == "TIMED_OUT")) | length) > 0
                        then "ci_failing"
                    elif ($c | map(select(.status != "COMPLETED")) | length) > 0 then
                        if ($c | map(select(
                                .conclusion == "SUCCESS" or
                                .conclusion == "NEUTRAL" or
                                .conclusion == "SKIPPED")) | length) > 0
                            then "ci_partial" else "ci_pending" end
                    else "ci_green"
                    end')

                printf '%s|%s|%s\n' "$repo" "$num" "$new_status" >> "$CI_TMP"
            fi
            ;;
    esac
done

# ── build jq inputs from temp files ──────────────────────────────────────────

merged_json='[]'
while IFS='|' read -r repo num date; do
    merged_json=$(printf '%s\n' "$merged_json" \
        | jq --arg r "$repo" --argjson n "$num" --arg d "$date" \
             '. + [{"repo": $r, "number": $n, "date": $d}]')
done < "$MERGED_TMP"

closed_json='[]'
while IFS='|' read -r repo num; do
    closed_json=$(printf '%s\n' "$closed_json" \
        | jq --arg r "$repo" --argjson n "$num" \
             '. + [{"repo": $r, "number": $n}]')
done < "$CLOSED_TMP"

ci_map='{}'
while IFS='|' read -r repo num status; do
    ci_map=$(printf '%s\n' "$ci_map" \
        | jq --arg k "${repo}|${num}" --arg s "$status" \
             '. + {($k): $s}')
done < "$CI_TMP"

# ── apply all changes in one jq pass ─────────────────────────────────────────
jq \
    --argjson merged  "$merged_json" \
    --argjson closed  "$closed_json" \
    --argjson ci_map  "$ci_map" \
    --arg     today   "$TODAY" '

  def in_list($arr):
    . as $self | $arr | any(.repo == $self.repo and .number == $self.number);

  # Partition open_prs
  (.open_prs | map(select(in_list($merged))))        as $to_merge  |
  (.open_prs | map(select(in_list($closed))))        as $to_close  |
  (.open_prs | map(
      select((in_list($merged) or in_list($closed)) | not)
    | . as $pr
    | ($pr.repo + "|" + ($pr.number | tostring)) as $k
    | if ($ci_map | has($k)) then . + {"status": $ci_map[$k]} else . end
  ))                                                 as $still_open |

  # Stamp MERGED date onto notes for entries moving to merged_recently
  ($to_merge | map(
    . as $pr |
    ([$merged[] | select(.repo == $pr.repo and .number == $pr.number)] | .[0].date // $today) as $d |
    $pr + {"notes": ($pr.notes + " MERGED \($d).")}
  ))                                                 as $newly_merged |

  .open_prs      = $still_open |
  .merged_recently = ($newly_merged + (.merged_recently // []))

' "$PR_FILE" > "${PR_FILE}.new"

mv "${PR_FILE}.new" "$PR_FILE"

# ── summary (this is what the LLM reads) ─────────────────────────────────────
n_merged=$(wc -l < "$MERGED_TMP" | tr -d '[:space:]')
n_closed=$(wc -l < "$CLOSED_TMP" | tr -d '[:space:]')

printf '\nopen-prs.json updated: %d open, %d merged, %d closed.\n' \
    "$n_unchanged" "$n_merged" "$n_closed"
[[ "$REFRESH_CI" == "true" ]] && \
    printf 'CI status refreshed for %d open PRs.\n' "$n_unchanged"
[[ "$n_merged" -eq 0 && "$n_closed" -eq 0 ]] && \
    printf 'No state changes — open_prs matches GitHub.\n'

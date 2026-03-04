#!/usr/bin/env bash
# sync-pr-state.sh
# Reconciles metadata/open-prs.json against actual GitHub PR state.
# Moves merged/closed PRs from open_prs into merged_recently.
# Prints a compact change summary — the JSON file is updated in-place.
#
# Usage:
#   sync-pr-state.sh                      # merge-state check only (fast: 1 API call/PR)
#   sync-pr-state.sh --ci                 # also refresh CI status (2 API calls/PR)
#   sync-pr-state.sh --approvals          # also check for human GitHub approvals (2 API calls/PR)
#   sync-pr-state.sh --ci --approvals     # both
#
# --approvals sets human_approved=true on PRs that have at least one APPROVED review
# from a non-bot GitHub user.  The Lead must check human_approved before notifying
# the human inbox that a PR is ready to merge.
#
# Run as Step 0 at the start of every lead session.
# The LLM reads ONLY the printed summary, not the full JSON — keep output brief.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_FILE="$SCRIPT_DIR/../metadata/open-prs.json"
REFRESH_CI=false
REFRESH_APPROVALS=false
for arg in "$@"; do
    case "$arg" in
        --ci)          REFRESH_CI=true ;;
        --approvals)   REFRESH_APPROVALS=true ;;
        *)             printf 'Unknown option: %s\n' "$arg" >&2; exit 1 ;;
    esac
done

# ── temp files (cleaned up on exit) ──────────────────────────────────────────
MERGED_TMP=$(mktemp)      # repo|number|date
CLOSED_TMP=$(mktemp)      # repo|number
CI_TMP=$(mktemp)          # repo|number|new_status        (--ci only)
APPROVALS_TMP=$(mktemp)   # repo|number|true|false        (--approvals only)
trap 'rm -f "$MERGED_TMP" "$CLOSED_TMP" "$CI_TMP" "$APPROVALS_TMP"' EXIT

TODAY=$(date -u +%Y-%m-%d)

# ── auto-migrate undocumented in_progress array ───────────────────────────────
# If the Lead hallucinated an in_progress sub-array, migrate entries into
# open_prs so they are visible to the sync loop.  Prints a warning so the
# Lead knows to stop creating sub-arrays.
in_progress_count=$(jq '(.in_progress // []) | length' "$PR_FILE")
if [[ "$in_progress_count" -gt 0 ]]; then
    printf 'WARNING: Found "in_progress" array (%d entries) — migrating to open_prs.\n' \
        "$in_progress_count"
    printf 'All tracked open PRs must be in open_prs. Do not create sub-arrays.\n'
    jq '
      .open_prs = (
        .open_prs +
        (.in_progress | map(
            . + (if has("status")         then {} else {"status": "ci_unknown"}  end)
              + (if has("human_approved") then {} else {"human_approved": false} end)
        ))
      ) |
      del(.in_progress)
    ' "$PR_FILE" > "${PR_FILE}.new"
    mv "${PR_FILE}.new" "$PR_FILE"
fi

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

            if [[ "$REFRESH_APPROVALS" == "true" ]]; then
                approval_data=$(gh pr view "$num" --repo "$repo" \
                    --json reviews 2>/dev/null \
                    || printf '{"reviews":[]}')

                # human_approved = true if any non-bot user has APPROVED
                approved=$(printf '%s\n' "$approval_data" | jq -r '
                    (.reviews // []) |
                    any(.state == "APPROVED" and
                        (.author.login | test("\\[bot\\]$") | not)) |
                    if . then "true" else "false" end')

                printf '%s|%s|%s\n' "$repo" "$num" "$approved" >> "$APPROVALS_TMP"
                [[ "$approved" == "true" ]] && \
                    printf '  APPROVED  %s#%s  (human GitHub approval present)\n' "$repo" "$num"
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

approval_map='{}'
while IFS='|' read -r repo num approved; do
    approval_map=$(printf '%s\n' "$approval_map" \
        | jq --arg k "${repo}|${num}" --argjson a "$approved" \
             '. + {($k): $a}')
done < "$APPROVALS_TMP"

# ── apply all changes in one jq pass ─────────────────────────────────────────
jq \
    --argjson merged        "$merged_json" \
    --argjson closed        "$closed_json" \
    --argjson ci_map        "$ci_map" \
    --argjson approval_map  "$approval_map" \
    --arg     today         "$TODAY" '

  def in_list($arr):
    . as $self | $arr | any(.repo == $self.repo and .number == $self.number);

  # Partition open_prs
  (.open_prs | map(select(in_list($merged))))        as $to_merge  |
  (.open_prs | map(select(in_list($closed))))        as $to_close  |
  (.open_prs | map(
      select((in_list($merged) or in_list($closed)) | not)
    | . as $pr
    | ($pr.repo + "|" + ($pr.number | tostring)) as $k
    | if ($ci_map      | has($k)) then . + {"status":         $ci_map[$k]}      else . end
    | if ($approval_map | has($k)) then . + {"human_approved": $approval_map[$k]} else . end
  ))                                                 as $still_open |

  # Stamp MERGED date onto notes for entries moving to merged_recently
  ($to_merge | map(
    . as $pr |
    ([$merged[] | select(.repo == $pr.repo and .number == $pr.number)] | .[0].date // $today) as $d |
    $pr + {"notes": ($pr.notes + " MERGED \($d).")}
  ))                                                 as $newly_merged |

  # Stamp CLOSED date onto notes for closed-without-merge entries
  ($to_close | map(
    . + {"notes": ((.notes // "") + " CLOSED (not merged) \($today).")}
  ))                                                 as $newly_closed |

  .open_prs      = $still_open |
  .merged_recently = (($newly_merged + $newly_closed + (.merged_recently // [])) | .[-50:])

' "$PR_FILE" > "${PR_FILE}.new"

mv "${PR_FILE}.new" "$PR_FILE"

# ── summary (this is what the LLM reads) ─────────────────────────────────────
n_merged=$(wc -l < "$MERGED_TMP" | tr -d '[:space:]')
n_closed=$(wc -l < "$CLOSED_TMP" | tr -d '[:space:]')

printf '\nopen-prs.json updated: %d open, %d merged, %d closed.\n' \
    "$n_unchanged" "$n_merged" "$n_closed"
[[ "$REFRESH_CI" == "true" ]] && \
    printf 'CI status refreshed for %d open PRs.\n' "$n_unchanged"
[[ "$REFRESH_APPROVALS" == "true" ]] && \
    printf 'Approval status refreshed for %d open PRs.\n' "$n_unchanged"
[[ "$n_merged" -eq 0 && "$n_closed" -eq 0 ]] && \
    printf 'No state changes — open_prs matches GitHub.\n'

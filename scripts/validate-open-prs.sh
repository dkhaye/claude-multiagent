#!/usr/bin/env bash
# validate-open-prs.sh — Validate metadata/open-prs.json structure.
#
# Checks:
#   - Valid JSON (jq can parse it)
#   - Required top-level keys: schema_version, open_prs, merged_recently
#   - Required fields per open PR entry: repo, number, status, human_approved
#   - Warns if merged_recently exceeds retention limit (50 entries)
#
# Usage:
#   validate-open-prs.sh [--file <path>]  # default: $WORKSPACE_ROOT/metadata/open-prs.json
#   validate-open-prs.sh --quiet          # suppress warnings, only show errors
#
# Exit codes:
#   0 — valid
#   1 — invalid (errors found)
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
PRS_FILE="$WORKSPACE_ROOT/metadata/open-prs.json"
QUIET=false
ERRORS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)  PRS_FILE="$2"; shift 2 ;;
    --quiet) QUIET=true;    shift   ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

err()  { echo "ERROR: $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { $QUIET || echo "WARN:  $*"; }
ok()   { $QUIET || echo "OK:    $*"; }

if [[ ! -f "$PRS_FILE" ]]; then
  err "File not found: $PRS_FILE"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  err "jq is required (brew install jq)"
  exit 1
fi

# 1. Valid JSON?
if ! jq empty "$PRS_FILE" 2>/dev/null; then
  err "Invalid JSON in $PRS_FILE"
  exit 1
fi
ok "JSON is valid"

# 2. Required top-level keys
for key in schema_version open_prs merged_recently; do
  if ! jq -e "has(\"$key\")" "$PRS_FILE" >/dev/null 2>&1; then
    err "Missing top-level key: $key"
  fi
done
[[ "$ERRORS" -eq 0 ]] && ok "Top-level keys present"

# 3. schema_version value
schema_ver=$(jq -r '.schema_version // "missing"' "$PRS_FILE")
if [[ "$schema_ver" != "2" ]]; then
  err "schema_version is '$schema_ver', expected 2. Run migrate-open-prs-v1-to-v2.sh."
else
  ok "schema_version = 2"
fi

# 4. Required fields per open_pr entry
open_count=$(jq '.open_prs | length' "$PRS_FILE")
entry_errors=0
for i in $(seq 0 $((open_count - 1))); do
  for field in repo number status human_approved; do
    if ! jq -e ".open_prs[$i] | has(\"$field\")" "$PRS_FILE" >/dev/null 2>&1; then
      entry_num=$(jq -r ".open_prs[$i].number // \"index $i\"" "$PRS_FILE")
      err "open_prs[$i] (PR #$entry_num): missing required field '$field'"
      entry_errors=$((entry_errors + 1))
    fi
  done
done
[[ "$entry_errors" -eq 0 ]] && ok "All $open_count open PR entries have required fields"

# 5. merged_recently retention warning
merged_count=$(jq '.merged_recently | length' "$PRS_FILE")
RETENTION_LIMIT=50
if [[ "$merged_count" -gt "$RETENTION_LIMIT" ]]; then
  warn "merged_recently has $merged_count entries (limit: $RETENTION_LIMIT). Run sync-pr-state.sh to trim."
else
  ok "merged_recently count = $merged_count (within $RETENTION_LIMIT limit)"
fi

# Result
if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "Validation FAILED: $ERRORS error(s) in $PRS_FILE"
  exit 1
else
  echo ""
  echo "Validation passed: $PRS_FILE"
fi

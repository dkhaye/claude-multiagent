#!/usr/bin/env bash
# migrate-open-prs-v1-to-v2.sh — Migrate open-prs.json to schema v2.
#
# Schema v2 format:
#   { "schema_version": 2, "open_prs": [...], "merged_recently": [...] }
#
# Handles:
#   - v1 schema: { "prs": [...] }          → rename prs → open_prs
#   - partial v2: open_prs present but missing schema_version or merged_recently
#   - already v2: no-op (exits 0)
#
# Applies merged_recently retention: keeps last 50 entries.
# Creates a timestamped backup before any modification.
#
# Usage:
#   migrate-open-prs-v1-to-v2.sh [--file <path>]
#
# Exit codes:
#   0 — success (migrated or already v2)
#   1 — error (invalid JSON, file not found, jq missing)
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
PRS_FILE="$WORKSPACE_ROOT/metadata/open-prs.json"
RETENTION_LIMIT=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) PRS_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$PRS_FILE" ]]; then
  echo "File not found: $PRS_FILE" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)" >&2
  exit 1
fi

# Validate JSON before anything
if ! jq empty "$PRS_FILE" 2>/dev/null; then
  echo "Error: $PRS_FILE is not valid JSON. Fix structural issues before migrating." >&2
  exit 1
fi

# Check if already schema v2
schema_ver=$(jq -r '.schema_version // "none"' "$PRS_FILE")
if [[ "$schema_ver" == "2" ]]; then
  echo "Already schema v2: $PRS_FILE — no migration needed."
  exit 0
fi

# Create backup
BACKUP="${PRS_FILE%.json}-backup-$(date +%Y%m%d-%H%M%S).json"
cp "$PRS_FILE" "$BACKUP"
echo "Backup created: $BACKUP"

# Determine migration path
has_prs=$(jq 'has("prs")' "$PRS_FILE")
has_open_prs=$(jq 'has("open_prs")' "$PRS_FILE")

if [[ "$has_prs" == "true" && "$has_open_prs" == "false" ]]; then
  echo "Detected v1 schema (prs key). Migrating to v2..."
  MIGRATE_JQ='
    {
      "schema_version": 2,
      "open_prs": (.prs // []),
      "merged_recently": ((.merged_recently // [])[-'"$RETENTION_LIMIT"':])
    }
  '
elif [[ "$has_open_prs" == "true" ]]; then
  echo "Detected partial v2 schema (open_prs key, missing schema_version). Upgrading..."
  MIGRATE_JQ='
    {
      "schema_version": 2,
      "open_prs": (.open_prs // []),
      "merged_recently": ((.merged_recently // [])[-'"$RETENTION_LIMIT"':])
    }
  '
else
  echo "Unrecognized schema (no prs or open_prs key). Creating empty v2 file." >&2
  MIGRATE_JQ='{"schema_version": 2, "open_prs": [], "merged_recently": []}'
fi

tmp="$(mktemp)"
jq "$MIGRATE_JQ" "$PRS_FILE" > "$tmp"
mv "$tmp" "$PRS_FILE"

open_count=$(jq '.open_prs | length' "$PRS_FILE")
merged_count=$(jq '.merged_recently | length' "$PRS_FILE")
echo "Migration complete: $open_count open PRs, $merged_count merged_recently entries."
echo "Run validate-open-prs.sh to confirm."

#!/usr/bin/env bash
# check-workspace-isolation.sh — Verify a project workspace has no cross-project contamination.
#
# Scans scripts/, prompts, and .claude-workspace/ CLAUDE.md files in a project
# workspace for references to OTHER project names. Catches cases where a file
# was accidentally copied from another project or a path substitution was wrong.
#
# Usage:
#   check-workspace-isolation.sh <project-workspace-path>
#
# Example:
#   check-workspace-isolation.sh ~/projects/[[PROJECT_NAME]]
#
# Exit codes:
#   0  clean — no cross-project references found
#   1  violations found
#
# Run this:
#   - Before launching agents in a new project for the first time
#   - After any manual file edit that involves paths or project references
#   - As part of a pre-launch sanity check in launch-agents.sh (optional)
#
set -euo pipefail

PROJECT_PATH="${1:-}"

if [[ -z "$PROJECT_PATH" ]]; then
  echo "Usage: check-workspace-isolation.sh <project-workspace-path>" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Error: project path not found: $PROJECT_PATH" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$PROJECT_PATH")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(dirname "$SCRIPT_DIR")"

VIOLATIONS=0

violation() {
  local file="$1" other="$2" match="$3"
  printf '  VIOLATION  %s\n' "$file"
  printf '    Contains reference to OTHER project: %s\n' "$other"
  printf '    Match:   %s\n' "$match"
  VIOLATIONS=$((VIOLATIONS + 1))
}

# ── Collect other known project names ────────────────────────────────────────
# Read from projects.json (sibling of the template root, inside .global/)
OTHER_PROJECTS=()
PROJECTS_JSON="$TEMPLATE_ROOT/../.global/projects.json"
if [[ -f "$PROJECTS_JSON" ]]; then
  while IFS= read -r name; do
    [[ "$name" == "$PROJECT_NAME" ]] && continue
    [[ -z "$name" ]] && continue
    OTHER_PROJECTS+=("$name")
  done < <(jq -r '.projects[].name' "$PROJECTS_JSON" 2>/dev/null || true)
fi

if [[ ${#OTHER_PROJECTS[@]} -eq 0 ]]; then
  echo "check-workspace-isolation: no other projects registered — nothing to check against."
  echo "(Add projects to $PROJECTS_JSON to enable cross-contamination checks.)"
  exit 0
fi

# ── Files to scan ─────────────────────────────────────────────────────────────
# scripts/, .claude-workspace/ CLAUDE.md files, launch-agents.sh, prompts
SCAN_DIRS=(
  "$PROJECT_PATH/scripts"
  "$PROJECT_PATH/.claude-workspace"
)
SCAN_FILES=("$PROJECT_PATH/launch-agents.sh")

# Collect all files
ALL_FILES_TMP=$(mktemp)
trap 'rm -f "$ALL_FILES_TMP"' EXIT

for dir in "${SCAN_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r f; do
      printf '%s\n' "$f" >> "$ALL_FILES_TMP"
    done < <(find "$dir" -type f \( -name "*.sh" -o -name "*.txt" -o -name "*.md" -o -name "*.json" \) 2>/dev/null || true)
  fi
done

for f in "${SCAN_FILES[@]}"; do
  [[ -f "$f" ]] && printf '%s\n' "$f" >> "$ALL_FILES_TMP"
done

# ── Scan ───────────────────────────────────────────────────────────────────────
printf 'check-workspace-isolation: scanning %s\n' "$PROJECT_NAME"
printf '  Checking for references to: %s\n\n' "${OTHER_PROJECTS[*]}"

while IFS= read -r full_path; do
  [[ -z "$full_path" ]] && continue
  [[ -f "$full_path" ]] || continue

  rel_path="${full_path#$PROJECT_PATH/}"

  for other in "${OTHER_PROJECTS[@]}"; do
    if grep -qF "$other" "$full_path" 2>/dev/null; then
      while IFS= read -r match; do
        violation "$rel_path" "$other" "$match"
      done < <(grep -nF "$other" "$full_path" | head -3)
    fi
  done

done < "$ALL_FILES_TMP"

# ── Summary ────────────────────────────────────────────────────────────────────
printf '\n'
if [[ $VIOLATIONS -eq 0 ]]; then
  printf 'check-workspace-isolation: PASSED — %s is isolated from other projects.\n' "$PROJECT_NAME"
  exit 0
else
  printf 'check-workspace-isolation: FAILED — %d cross-project reference(s) found in %s.\n\n' \
    "$VIOLATIONS" "$PROJECT_NAME"
  printf 'Each file shown above contains a reference to another project workspace.\n'
  printf 'Fix by:\n'
  printf '  - Replacing hardcoded project names with [[PROJECT_NAME]] in template source\n'
  printf '  - Re-running sync-from-template.sh to regenerate the affected script\n'
  printf '  - Or manually correcting the reference if it was a copy-paste error\n'
  exit 1
fi

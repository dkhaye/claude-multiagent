#!/usr/bin/env bash
# check-template-purity.sh — Verify the template repo contains no project-specific content.
#
# Scans all tracked files in the template repo against two rule sets:
#
#   1. Blocklist (.template-blocklist): strings that must never appear.
#      Maintained by the Global CC — update when adding a new project.
#
#   2. Pattern check: any ~/projects/<word> where <word> is not a placeholder
#      ([[PROJECT_NAME]], [[PROJECT_ROOT]]) or the hub directory (.global).
#      Catches hardcoded project paths not yet in the blocklist.
#
# Usage (from template root):
#   scripts/check-template-purity.sh              # scan tracked files only
#   scripts/check-template-purity.sh --all        # scan all files (including untracked)
#   scripts/check-template-purity.sh --staged     # scan staged files only (pre-commit)
#
# Exit codes:
#   0  clean — no violations found
#   1  violations found — commit/push must be blocked
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(dirname "$SCRIPT_DIR")"
BLOCKLIST="$TEMPLATE_ROOT/.template-blocklist"

MODE="${1:-}"

VIOLATIONS=0

# ── violation helper ───────────────────────────────────────────────────────────
violation() {
  local file="$1" rule="$2" match="$3"
  printf '  VIOLATION  %s\n' "$file"
  printf '    Rule:    %s\n' "$rule"
  printf '    Match:   %s\n' "$match"
  VIOLATIONS=$((VIOLATIONS + 1))
}

# ── collect files to scan ─────────────────────────────────────────────────────
FILES_TMP=$(mktemp)
trap 'rm -f "$FILES_TMP"' EXIT

case "$MODE" in
  --staged)
    git -C "$TEMPLATE_ROOT" diff --cached --name-only --diff-filter=ACM >> "$FILES_TMP"
    ;;
  --all)
    git -C "$TEMPLATE_ROOT" ls-files >> "$FILES_TMP"
    git -C "$TEMPLATE_ROOT" ls-files --others --exclude-standard >> "$FILES_TMP"
    ;;
  *)
    git -C "$TEMPLATE_ROOT" ls-files >> "$FILES_TMP"
    ;;
esac

# ── load blocklist entries into a temp file ───────────────────────────────────
ENTRIES_TMP=$(mktemp)
trap 'rm -f "$FILES_TMP" "$ENTRIES_TMP"' EXIT

if [[ -f "$BLOCKLIST" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    printf '%s\n' "$line" >> "$ENTRIES_TMP"
  done < "$BLOCKLIST"
else
  printf 'WARNING: No .template-blocklist found — project-specific string check skipped.\n' >&2
  printf '  Create %s with your project names and paths to enable this check.\n' "$BLOCKLIST" >&2
fi

# ── scan each file ─────────────────────────────────────────────────────────────
while IFS= read -r rel_path; do
  [[ -z "$rel_path" ]] && continue
  full_path="$TEMPLATE_ROOT/$rel_path"
  [[ -f "$full_path" ]] || continue

  # Skip binary files
  if ! file "$full_path" | grep -q "text"; then
    continue
  fi

  # Skip this script and the blocklist itself (they reference the terms by design)
  case "$rel_path" in
    scripts/check-template-purity.sh|\
    scripts/install-template-hooks.sh|\
    .template-blocklist)
      continue ;;
  esac

  # ── Rule 1: blocklist entries ──────────────────────────────────────────────
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if grep -qF "$entry" "$full_path" 2>/dev/null; then
      while IFS= read -r match; do
        violation "$rel_path" "blocklist: $entry" "$match"
      done < <(grep -nF "$entry" "$full_path" | head -3)
    fi
  done < "$ENTRIES_TMP"

  # ── Rule 2: ~/projects/<word> where <word> is not a placeholder or .global ──
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    # Allow: ~/projects/[[...]], ~/projects/.global
    case "$match" in
      *'~/projects/[['*|*'~/projects/.global'*)
        continue ;;
    esac
    violation "$rel_path" "hardcoded ~/projects/ path (use ~/projects/[[PROJECT_NAME]]/ instead)" "$match"
  done < <(grep -onE '~/projects/[^[:space:]"'"'"'`\\]+' "$full_path" 2>/dev/null || true)

done < "$FILES_TMP"

# ── summary ────────────────────────────────────────────────────────────────────
printf '\n'
if [[ $VIOLATIONS -eq 0 ]]; then
  printf 'check-template-purity: PASSED — no project-specific content found.\n'
  exit 0
else
  printf 'check-template-purity: FAILED — %d violation(s) found.\n\n' "$VIOLATIONS"
  printf 'The template repo must be 100%% project-agnostic.\n'
  printf '  - Replace specific project names with [[PROJECT_NAME]]\n'
  printf '  - Replace specific paths with ~/projects/[[PROJECT_NAME]]/...\n'
  printf '  - Move project-specific content (repos, orgs) to the project CLAUDE.md files\n'
  printf '  - Update .template-blocklist when adding new projects\n'
  exit 1
fi

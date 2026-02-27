#!/usr/bin/env bash
# Remove worktrees for a feature and update the registry.
#
# Usage:
#   cleanup-worktrees.sh <feature-name> [options]
#
# Options:
#   --remove-branches   Delete the local feature branch from each repo after removing the worktree
#   --archive           Move worktree dir to worktrees/.archive/ instead of deleting (useful if PR not yet merged)
#
# Always marks registry entries for the feature as "complete".
# Also cleans feature-scoped temp: metadata/tmp/feature/<feature-name>/ if it exists.
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
REPOS_ROOT="$WORKSPACE_ROOT/repos"
WORKTREES_ROOT="$WORKSPACE_ROOT/worktrees"
REGISTRY="$WORKSPACE_ROOT/metadata/worktree-registry.json"
ARCHIVE_ROOT="$WORKTREES_ROOT/.archive"

FEATURE="${1:?Usage: $0 <feature-name> [--remove-branches] [--archive]}"
REMOVE_BRANCHES=false
DO_ARCHIVE=false

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-branches) REMOVE_BRANCHES=true; shift ;;
    --archive)         DO_ARCHIVE=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

FEATURE_DIR="$WORKTREES_ROOT/$FEATURE"
if [[ ! -d "$FEATURE_DIR" ]]; then
  echo "No worktrees found for feature: $FEATURE (already cleaned?)" >&2
fi

if [[ -d "$FEATURE_DIR" ]]; then
  if $DO_ARCHIVE; then
    mkdir -p "$ARCHIVE_ROOT"
    mv "$FEATURE_DIR" "$ARCHIVE_ROOT/$FEATURE-$(date +%Y%m%d)"
    echo "Archived to: $ARCHIVE_ROOT/$FEATURE-$(date +%Y%m%d)"
  else
    for wt in "$FEATURE_DIR"/*/; do
      [[ -d "$wt/.git" ]] || continue
      repo_name="$(basename "$wt")"
      main_repo="$REPOS_ROOT/$repo_name"
      echo "Removing worktree: $wt"
      git -C "$main_repo" worktree remove "$wt" --force 2>/dev/null || true
      if $REMOVE_BRANCHES; then
        branch="$FEATURE"
        git -C "$main_repo" branch -D "$branch" 2>/dev/null || true
        echo "  Deleted branch: $branch in $repo_name"
      fi
    done
    rmdir "$FEATURE_DIR" 2>/dev/null || true
    echo "Cleanup done for feature: $FEATURE"
  fi
fi

# --- Update worktree-registry.json ---
if [[ -f "$REGISTRY" ]] && command -v jq &>/dev/null; then
  tmp="$(mktemp)"
  jq --arg feature "$FEATURE" \
    '(.worktrees[] | select(.feature == $feature)).status = "complete"' \
    "$REGISTRY" > "$tmp"
  mv "$tmp" "$REGISTRY"
  echo "Registry updated: marked '$FEATURE' entries as complete"
fi

# --- Clean feature-scoped temp ---
FEATURE_TMP="$WORKSPACE_ROOT/metadata/tmp/feature/$FEATURE"
if [[ -d "$FEATURE_TMP" ]]; then
  rm -rf "$FEATURE_TMP"
  echo "Cleaned feature temp: $FEATURE_TMP"
fi

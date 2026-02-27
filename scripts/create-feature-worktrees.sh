#!/usr/bin/env bash
# Create git worktrees for a feature across one or more repos.
#
# Usage:
#   create-feature-worktrees.sh <feature-name> [options] [repo1 repo2 ...]
#
# Options:
#   --branch <name>   Branch name to create (default: same as feature-name)
#   --base <ref>      Git ref to branch from (default: current HEAD of each repo)
#   --repo <name>     Repo to create worktree in (repeatable; positional repos also accepted)
#   --list            List active worktrees from registry and exit
#
# If no repos given (positional or --repo), uses all repos in repos/.
# Safe to run multiple times: skips repos where the worktree already exists.
set -euo pipefail

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects/[[PROJECT_NAME]]}"
REPOS_ROOT="$WORKSPACE_ROOT/repos"
WORKTREES_ROOT="$WORKSPACE_ROOT/worktrees"
REGISTRY="$WORKSPACE_ROOT/metadata/worktree-registry.json"

# --- Parse arguments ---
FEATURE=""
BRANCH=""
BASE=""
REPOS=()
LIST_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --base)   BASE="$2";   shift 2 ;;
    --repo)   REPOS+=("$2"); shift 2 ;;
    --list)   LIST_MODE=true; shift ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$FEATURE" ]]; then
        FEATURE="$1"
      else
        REPOS+=("$1")
      fi
      shift ;;
  esac
done

# --- List mode ---
if $LIST_MODE; then
  if [[ ! -f "$REGISTRY" ]]; then
    echo "No registry found at $REGISTRY"
    exit 0
  fi
  if ! command -v jq &>/dev/null; then
    echo "jq required for --list"
    exit 1
  fi
  echo ""
  printf "%-30s %-30s %-25s %-10s %s\n" "FEATURE" "REPO" "BRANCH" "STATUS" "EXISTS"
  printf "%-30s %-30s %-25s %-10s %s\n" "-------" "----" "------" "------" "------"
  jq -r '.worktrees[] | [.feature, .repo, (.branch // "?"), .status, .path] | @tsv' "$REGISTRY" | \
  while IFS=$'\t' read -r feature repo branch status path; do
    expanded="${path/\~/$HOME}"
    if [[ -d "$expanded" ]]; then exists="yes"; else exists="NO"; fi
    printf "%-30s %-30s %-25s %-10s %s\n" "$feature" "$repo" "$branch" "$status" "$exists"
  done
  echo ""
  exit 0
fi

if [[ -z "$FEATURE" ]]; then
  echo "Usage: $0 <feature-name> [--branch <name>] [--base <ref>] [--repo <name>...] [repo1 repo2...]" >&2
  exit 1
fi

BRANCH="${BRANCH:-$FEATURE}"

# If no repos specified, use all repos under repos/
if [[ ${#REPOS[@]} -eq 0 ]]; then
  for d in "$REPOS_ROOT"/*/; do
    [[ -d "$d/.git" ]] || continue
    REPOS+=( "$(basename "$d")" )
  done
fi

mkdir -p "$WORKTREES_ROOT/$FEATURE"
CREATED=()

for repo in "${REPOS[@]}"; do
  SRC="$REPOS_ROOT/$repo"
  DST="$WORKTREES_ROOT/$FEATURE/$repo"
  if [[ ! -d "$SRC/.git" ]]; then
    echo "Skip (not a repo): $repo" >&2
    continue
  fi
  if [[ -d "$DST" ]]; then
    echo "Exists: $DST"
    continue
  fi
  if [[ -n "$BASE" ]]; then
    git -C "$SRC" worktree add -b "$BRANCH" "$DST" "$BASE"
  else
    git -C "$SRC" worktree add -b "$BRANCH" "$DST"
  fi
  CREATED+=( "$DST" )
  echo "Created: $DST (branch: $BRANCH)"
done

# --- Update worktree-registry.json ---
if [[ ${#CREATED[@]} -gt 0 ]] && [[ -f "$REGISTRY" ]] && command -v jq &>/dev/null; then
  for path in "${CREATED[@]}"; do
    repo_name="$(basename "$path")"
    entry=$(jq -n \
      --arg feature "$FEATURE" \
      --arg repo "$repo_name" \
      --arg branch "$BRANCH" \
      --arg path "~/${path#"$HOME/"}" \
      --arg created "$(date +%Y-%m-%d)" \
      '{feature: $feature, repo: $repo, branch: $branch, path: $path, created: $created, status: "active"}')
    tmp="$(mktemp)"
    jq --argjson entry "$entry" '.worktrees += [$entry]' "$REGISTRY" > "$tmp"
    mv "$tmp" "$REGISTRY"
  done
  echo "Registry updated: $REGISTRY"
fi

echo "Feature worktrees for '$FEATURE': $WORKTREES_ROOT/$FEATURE/"

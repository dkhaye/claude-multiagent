#!/usr/bin/env bash
# verify-repo-facts.sh — Detect and print key facts about a repository.
#
# Run this ONCE before making code changes in a new worktree to surface
# the default branch, package manager, Node version, and test commands.
# Prevents guessing defaults, which is a common source of CI churn.
#
# Usage: verify-repo-facts.sh <repo-path>
#
# Exit codes:
#   0 — facts printed; all required facts could be determined
#   1 — one or more required facts (default branch) could not be determined;
#       do not proceed — ask Lead or human for the missing information
set -euo pipefail

REPO_PATH="${1:?Usage: verify-repo-facts.sh <repo-path>}"

if [[ ! -d "$REPO_PATH" ]]; then
  echo "Error: directory not found: $REPO_PATH" >&2
  exit 1
fi

ERRORS=0

echo "=== Repository facts: $REPO_PATH ==="
echo ""

# --- Default branch ---
DEFAULT_BRANCH=""
# Try remote show origin first (most reliable)
DEFAULT_BRANCH=$(git -C "$REPO_PATH" remote show origin 2>/dev/null \
  | awk '/HEAD branch:/{print $NF}' || true)
# Fallback: check remote refs
if [[ -z "$DEFAULT_BRANCH" ]]; then
  if git -C "$REPO_PATH" rev-parse --verify origin/main &>/dev/null 2>&1; then
    DEFAULT_BRANCH="main"
  elif git -C "$REPO_PATH" rev-parse --verify origin/master &>/dev/null 2>&1; then
    DEFAULT_BRANCH="master"
  fi
fi
if [[ -z "$DEFAULT_BRANCH" ]]; then
  echo "Default branch: UNKNOWN"
  echo "  ERROR: Cannot determine default branch — required for PR base." >&2
  ERRORS=$((ERRORS + 1))
else
  echo "Default branch: $DEFAULT_BRANCH"
fi

# --- Package manager + lockfile ---
if [[ -f "$REPO_PATH/package.json" ]]; then
  if [[ -f "$REPO_PATH/yarn.lock" ]]; then
    LOCKFILE="yarn.lock"
    # Check if using corepack (packageManager field in package.json)
    PKG_MGR_FIELD=""
    if command -v jq &>/dev/null; then
      PKG_MGR_FIELD=$(jq -r '.packageManager // empty' "$REPO_PATH/package.json" 2>/dev/null || true)
    fi
    if [[ -n "$PKG_MGR_FIELD" ]]; then
      echo "Package manager: yarn (corepack: $PKG_MGR_FIELD)"
    else
      echo "Package manager: yarn"
    fi
  elif [[ -f "$REPO_PATH/pnpm-lock.yaml" ]]; then
    LOCKFILE="pnpm-lock.yaml"
    echo "Package manager: pnpm"
  elif [[ -f "$REPO_PATH/package-lock.json" ]]; then
    LOCKFILE="package-lock.json"
    echo "Package manager: npm"
  else
    LOCKFILE="none"
    echo "Package manager: npm (no lockfile found)"
  fi
  echo "Lockfile: $LOCKFILE"
else
  echo "Package manager: none (no package.json)"
  echo "Lockfile: none"
fi

# --- Node version ---
NODE_VERSION="none"
NODE_SOURCE="none"
if [[ -f "$REPO_PATH/.nvmrc" ]]; then
  NODE_VERSION=$(tr -d '[:space:]' < "$REPO_PATH/.nvmrc")
  NODE_SOURCE=".nvmrc"
elif [[ -f "$REPO_PATH/package.json" ]] && command -v jq &>/dev/null; then
  ENGINES_NODE=$(jq -r '.engines.node // empty' "$REPO_PATH/package.json" 2>/dev/null || true)
  if [[ -n "$ENGINES_NODE" ]]; then
    NODE_VERSION="$ENGINES_NODE"
    NODE_SOURCE="package.json#engines.node"
  fi
fi
echo "Node version: $NODE_VERSION (source: $NODE_SOURCE)"

# --- Scripts from package.json ---
if [[ -f "$REPO_PATH/package.json" ]] && command -v jq &>/dev/null; then
  TEST_CMD=$(jq -r '.scripts.test // empty' "$REPO_PATH/package.json" 2>/dev/null || true)
  LINT_CMD=$(jq -r '.scripts.lint // empty' "$REPO_PATH/package.json" 2>/dev/null || true)
  BUILD_CMD=$(jq -r '.scripts.build // empty' "$REPO_PATH/package.json" 2>/dev/null || true)
  echo "Test command:  ${TEST_CMD:-NONE}"
  echo "Lint command:  ${LINT_CMD:-NONE}"
  echo "Build command: ${BUILD_CMD:-NONE}"
fi

# --- Terraform ---
TF_FILES=$(git -C "$REPO_PATH" ls-files '*.tf' 2>/dev/null | head -1 || true)
if [[ -n "$TF_FILES" ]]; then
  echo "Terraform: YES"
else
  echo "Terraform: NO"
fi

echo ""

if [[ $ERRORS -gt 0 ]]; then
  echo "RESULT: INCOMPLETE — $ERRORS required fact(s) could not be determined." >&2
  echo "Do NOT proceed by guessing. Ask Lead or human for the missing information." >&2
  exit 1
fi

echo "RESULT: OK"

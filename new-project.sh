#!/usr/bin/env bash
# new-project.sh — Bootstrap a new multi-agent workspace from this template.
#
# Usage:
#   new-project.sh <project-name> [--dest <destination-dir>] [--authors N]
#
# Creates a new project directory by copying this template and substituting
# [[PROJECT_NAME]] and [[NUM_AUTHORS]] placeholders throughout. Then initialises
# git, creates a beads-central database, and prints next steps.
#
# Prerequisites: git, gh (GitHub CLI), bd (beads).
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_NAME="${1:-}"
DEST_DIR=""
NUM_AUTHORS=3

# --- Parse args ---
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      DEST_DIR="$2"
      shift 2
      ;;
    --authors)
      NUM_AUTHORS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_NAME" ]]; then
  echo "Usage: new-project.sh <project-name> [--dest <destination-dir>] [--authors N]" >&2
  echo "" >&2
  echo "  project-name   Short identifier for the project (e.g. my-project)" >&2
  echo "                 Used as tmux session name, directory name, and path prefix." >&2
  echo "  --dest DIR     Parent directory for the new project (default: ~/projects)" >&2
  echo "  --authors N    Number of Author agents (default: 3)" >&2
  exit 1
fi

# Validate author count
if ! [[ "$NUM_AUTHORS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --authors must be a positive integer." >&2
  exit 1
fi

# Validate project name: alphanumeric + hyphens only
if ! [[ "$PROJECT_NAME" =~ ^[a-z0-9-]+$ ]]; then
  echo "Error: project name must be lowercase alphanumeric with hyphens only." >&2
  exit 1
fi

DEST_PARENT="${DEST_DIR:-$HOME/projects}"
DEST="$DEST_PARENT/$PROJECT_NAME"

if [[ -e "$DEST" ]]; then
  echo "Error: destination already exists: $DEST" >&2
  exit 1
fi

echo "Creating project '$PROJECT_NAME' at $DEST ..."
echo ""

# --- Copy template ---
cp -r "$TEMPLATE_DIR" "$DEST"

# Remove template-specific files that should not carry over
rm -f "$DEST/new-project.sh"
rm -rf "$DEST/.git"

# --- Substitute [[PROJECT_NAME]] and [[NUM_AUTHORS]] in all text files ---
echo "Substituting [[PROJECT_NAME]] → $PROJECT_NAME, [[NUM_AUTHORS]] → $NUM_AUTHORS ..."
find "$DEST" -type f \( -name "*.sh" -o -name "*.md" -o -name "*.txt" -o -name "*.json" -o -name "CLAUDE.md" \) \
  -exec sed -i '' -e "s/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g" -e "s/\[\[NUM_AUTHORS\]\]/$NUM_AUTHORS/g" {} +

# --- Copy metadata-template to metadata ---
echo "Initialising metadata/ from metadata-template/ ..."
cp -r "$DEST/metadata-template/." "$DEST/metadata/"

# --- Create per-author inbox and session-tmp directories ---
echo "Creating author directories (1 to $NUM_AUTHORS) ..."
for i in $(seq 1 "$NUM_AUTHORS"); do
  mkdir -p "$DEST/metadata/messages/author-$i"
  touch "$DEST/metadata/messages/author-$i/.gitkeep"
  mkdir -p "$DEST/metadata/tmp/session/author-$i"
  touch "$DEST/metadata/tmp/session/author-$i/.gitkeep"
done

# --- Copy workspace templates ---
echo "Initialising .claude-workspace/ from .claude-workspace-template/ ..."
cp -r "$DEST/.claude-workspace-template/." "$DEST/.claude-workspace/"

# --- Create repos/ and worktrees/ directories ---
mkdir -p "$DEST/repos"
mkdir -p "$DEST/worktrees"

# --- Initialise beads-central ---
echo "Initialising beads-central/ ..."
mkdir -p "$DEST/beads-central"
(cd "$DEST/beads-central" && bd init) || {
  echo "Warning: bd init failed. You may need to initialise beads-central manually." >&2
}

# --- Git init ---
echo "Initialising git repo ..."
git -C "$DEST" init
git -C "$DEST" add .
git -C "$DEST" commit -m "chore: initial project scaffold from claude-multiagent template

Project: $PROJECT_NAME
Authors: $NUM_AUTHORS
Template: $(git -C "$TEMPLATE_DIR" rev-parse --short HEAD 2>/dev/null || echo 'unknown')
"

# --- Register in ~/.cc/projects.json ---
CC_DIR="${HOME}/.cc"
mkdir -p "$CC_DIR"
REGISTRY="$CC_DIR/projects.json"
if [[ ! -f "$REGISTRY" ]]; then
  echo '{"projects":[]}' > "$REGISTRY"
fi
if command -v jq &>/dev/null; then
  TMP_REGISTRY="$(mktemp)"
  jq --arg name "$PROJECT_NAME" --arg path "$DEST" \
    '.projects += [{"name": $name, "path": $path, "status": "active"}]' \
    "$REGISTRY" > "$TMP_REGISTRY"
  mv "$TMP_REGISTRY" "$REGISTRY"
  echo "Registered '$PROJECT_NAME' in $REGISTRY"
else
  echo "Warning: jq not found — skipping ~/.cc/projects.json registration." >&2
  echo "  Install jq (brew install jq) and add this entry manually:" >&2
  printf '  {"name":"%s","path":"%s","status":"active"}\n' "$PROJECT_NAME" "$DEST" >&2
fi

# Install global-status.sh to ~/.cc/ (always overwrite with latest version)
cp "$TEMPLATE_DIR/scripts/global-status.sh" "$CC_DIR/global-status.sh"
chmod +x "$CC_DIR/global-status.sh"
echo "Installed ~/.cc/global-status.sh"

echo ""
echo "=========================================="
echo " Project '$PROJECT_NAME' created at:"
echo " $DEST"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Edit $DEST/.claude-workspace/{lead-agent,author-template,reviewer,command-center}/CLAUDE.md"
echo "     Fill in the '## Project Configuration' section in each file."
echo "  2. Edit $DEST/scripts/env.sh — set any project-specific env vars."
echo "  3. Clone your repos into $DEST/repos/:"
echo "     git clone <url> $DEST/repos/<repo-name>"
echo "  4. (Optional) Create a GitHub repo for this workspace:"
echo "     gh repo create <org>/$PROJECT_NAME --private --source $DEST"
echo "  5. Launch agents:"
echo "     cd $DEST && ./launch-agents.sh"
echo "  6. Open the command center in a new terminal:"
echo "     cd $DEST/.claude-workspace/command-center && claude"
echo "  7. Check status across all projects:"
echo "     ~/.cc/global-status.sh"
echo ""

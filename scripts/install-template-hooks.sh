#!/usr/bin/env bash
# install-template-hooks.sh — Install git hooks that enforce template purity.
#
# Run this once after cloning the template repo (dkhaye/claude-multiagent).
# The hooks prevent committing or pushing project-specific content.
#
# Hooks installed:
#   pre-commit  — runs check-template-purity.sh --staged before each commit
#   pre-push    — runs check-template-purity.sh (all tracked files) before each push
#
# Usage:
#   scripts/install-template-hooks.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$TEMPLATE_ROOT/.git/hooks"

if [[ ! -d "$HOOKS_DIR" ]]; then
  echo "Error: .git/hooks not found — run this from inside the template repo." >&2
  exit 1
fi

# ── pre-commit ─────────────────────────────────────────────────────────────────
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/usr/bin/env bash
# Pre-commit: block project-specific content from entering the template.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
echo "--- check-template-purity (staged files) ---"
"$TEMPLATE_ROOT/scripts/check-template-purity.sh" --staged
HOOK
chmod +x "$HOOKS_DIR/pre-commit"
echo "Installed: .git/hooks/pre-commit"

# ── pre-push ───────────────────────────────────────────────────────────────────
cat > "$HOOKS_DIR/pre-push" << 'HOOK'
#!/usr/bin/env bash
# Pre-push: full scan of all tracked files before pushing to GitHub.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
echo "--- check-template-purity (all tracked files) ---"
"$TEMPLATE_ROOT/scripts/check-template-purity.sh"
HOOK
chmod +x "$HOOKS_DIR/pre-push"
echo "Installed: .git/hooks/pre-push"

echo ""
echo "Template purity hooks installed. They will run automatically on commit and push."
echo "To run manually: scripts/check-template-purity.sh"

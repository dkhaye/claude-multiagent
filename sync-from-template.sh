#!/usr/bin/env bash
# sync-from-template.sh — Sync a project workspace from the claude-multiagent template.
#
# Usage: sync-from-template.sh <project-workspace-path>
#
# What this script does (mechanical, auto-applied):
#   1. Copies new or updated scripts from the template into the project
#   2. Creates any missing inbox/tmp directories
#
# What this script does NOT do (requires Master CC / AI session):
#   3. CLAUDE.md updates — semantically complex, project-specific content must be preserved
#   4. settings.local.json permission changes — project-specific, reviewed manually
#
# After running this script, review the sync report and apply CLAUDE.md changes
# manually in the project's CC session or via the Master CC.
#
set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="${1:-}"

if [[ -z "$PROJECT_PATH" ]]; then
  echo "Usage: sync-from-template.sh <project-workspace-path>" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Error: project path not found: $PROJECT_PATH" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$PROJECT_PATH")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$PROJECT_PATH/metadata/sync-report-$TIMESTAMP.md"

log() { echo "$1" | tee -a "$REPORT"; }

log "# Template Sync Report — $TIMESTAMP"
log ""
log "Project: \`$PROJECT_PATH\`"
log "Template: \`$TEMPLATE_ROOT\`"
log ""

# ── 1. Scripts ─────────────────────────────────────────────────────────────────
log "## Scripts"
log ""

SCRIPTS=(
  agent-loop.sh
  beads-publish.sh
  cleanup-worktrees.sh
  create-feature-worktrees.sh
  env.sh
  validate-path.sh
  yarn-cwd.sh
)

mkdir -p "$PROJECT_PATH/scripts"

for script in "${SCRIPTS[@]}"; do
  SRC="$TEMPLATE_ROOT/scripts/$script"
  DST="$PROJECT_PATH/scripts/$script"

  if [[ ! -f "$SRC" ]]; then
    log "- SKIP: \`scripts/$script\` not in template"
    continue
  fi

  # Substitute [[PROJECT_NAME]] placeholder
  RENDERED="$(sed "s/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g" "$SRC")"

  if [[ ! -f "$DST" ]]; then
    echo "$RENDERED" > "$DST"
    chmod +x "$DST" 2>/dev/null || true
    log "- **ADDED**: \`scripts/$script\` (new in template)"
  else
    EXISTING="$(cat "$DST")"
    if [[ "$EXISTING" == "$RENDERED" ]]; then
      log "- ok: \`scripts/$script\`"
    else
      log "- **DIFFERS**: \`scripts/$script\` — template has changes; review and apply manually"
      log "  (Run: diff $DST <(sed 's/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g' $SRC))"
    fi
  fi
done

log ""

# ── 2. Directories ──────────────────────────────────────────────────────────────
log "## Directories"
log ""

# Author count — detect from existing author-N inbox dirs or default to 3
NUM_AUTHORS=3
for n in 1 2 3 4; do
  if [[ -d "$PROJECT_PATH/.claude-workspace/author-$n" ]]; then
    NUM_AUTHORS=$n
  fi
done

DIRS=(
  "metadata/messages/lead"
  "metadata/messages/reviewer"
  "metadata/messages/human"
  "metadata/tmp/beads"
  "metadata/tmp/session/reviewer"
  "metadata/logs"
  "metadata/learnings"
)

for n in $(seq 1 "$NUM_AUTHORS"); do
  DIRS+=("metadata/messages/author-$n")
  DIRS+=("metadata/tmp/session/author-$n")
done

for dir in "${DIRS[@]}"; do
  FULL="$PROJECT_PATH/$dir"
  if [[ ! -d "$FULL" ]]; then
    mkdir -p "$FULL"
    touch "$FULL/.gitkeep"
    log "- **CREATED**: \`$dir/\`"
  else
    log "- ok: \`$dir/\`"
  fi
done

log ""

# ── 3. CLAUDE.md — manual review checklist ─────────────────────────────────────
log "## CLAUDE.md files — manual review required"
log ""
log "The template CLAUDE.md files are at: \`$TEMPLATE_ROOT/.claude-workspace-template/\`"
log "Compare each role's CLAUDE.md against the template and apply structural changes."
log "Preserve all project-specific content (repo lists, languages, ticket refs, paths)."
log ""

ROLES=(command-center lead-agent reviewer author-template)
for role in "${ROLES[@]}"; do
  TMPL_MD="$TEMPLATE_ROOT/.claude-workspace-template/$role/CLAUDE.md"
  PROJ_MD="$PROJECT_PATH/.claude-workspace/$role/CLAUDE.md"

  if [[ ! -f "$TMPL_MD" ]]; then
    log "- SKIP: \`$role/CLAUDE.md\` not in template"
    continue
  fi

  if [[ ! -f "$PROJ_MD" ]]; then
    log "- **MISSING**: \`$role/CLAUDE.md\` — project has no file for this role"
    continue
  fi

  # Compare section headers as a quick structural diff
  TMPL_SECTIONS="$(grep '^## ' "$TMPL_MD" || true)"
  PROJ_SECTIONS="$(grep '^## ' "$PROJ_MD" || true)"

  if [[ "$TMPL_SECTIONS" == "$PROJ_SECTIONS" ]]; then
    log "- ok (same sections): \`.claude-workspace/$role/CLAUDE.md\`"
  else
    log "- **REVIEW**: \`.claude-workspace/$role/CLAUDE.md\` — section structure differs from template"
    log "  Template sections:"
    echo "$TMPL_SECTIONS" | while IFS= read -r line; do log "    $line"; done
    log "  Project sections:"
    echo "$PROJ_SECTIONS" | while IFS= read -r line; do log "    $line"; done
  fi
done

log ""
log "---"
log "Sync complete. Apply CLAUDE.md changes in the project CC session or via Master CC, then commit."
log ""
log "To commit the mechanical changes applied by this script:"
log "  git -C $PROJECT_PATH add scripts/ metadata/ && git -C $PROJECT_PATH commit -m 'chore: sync from template $TIMESTAMP'"

echo ""
echo "Report written to: $REPORT"

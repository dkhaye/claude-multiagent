#!/usr/bin/env bash
# sync-from-template.sh — Sync a project workspace from the claude-multiagent template.
#
# Usage: sync-from-template.sh <project-workspace-path>
#
# What this script does (mechanical, auto-applied):
#   1. Copies new or updated scripts/ from the template into the project
#   2. Copies new or updated root-level scripts (launch-agents.sh, etc.)
#   3. Creates any missing inbox/tmp directories
#
# What this script does NOT do (requires Global CC / AI session):
#   4. CLAUDE.md updates — semantically complex, project-specific content must be preserved
#   5. settings.local.json permission changes — project-specific, reviewed manually
#
# After running this script, review the sync report and apply CLAUDE.md changes
# manually in the project's CC session or via the Global CC.
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

# ── Load known project names for cross-contamination check ──────────────────
# Read from projects.json if available; always exclude the current project.
BLOCKLIST_FILE="$TEMPLATE_ROOT/.template-blocklist"
OTHER_PROJECTS=()
if [[ -f "$TEMPLATE_ROOT/../projects.json" ]]; then
  while IFS= read -r name; do
    [[ "$name" == "$PROJECT_NAME" ]] && continue
    [[ -z "$name" ]] && continue
    OTHER_PROJECTS+=("$name")
  done < <(jq -r '.projects[].name' "$TEMPLATE_ROOT/../projects.json" 2>/dev/null || true)
fi

# ── Validate a rendered script for contamination ─────────────────────────────
# $1 = script name (for logging), $2 = rendered content, $3 = destination path (optional)
validate_rendered() {
  local script_name="$1"
  local rendered="$2"
  local VALID=true

  # Rule 1: No unsubstituted [[...]] placeholders
  if echo "$rendered" | grep -qE '\[\[[A-Z_]+\]\]'; then
    log "  - **ERROR**: \`scripts/$script_name\` has unsubstituted placeholders after render:"
    echo "$rendered" | grep -nE '\[\[[A-Z_]+\]\]' | head -3 | while IFS= read -r line; do
      log "    $line"
    done
    VALID=false
  fi

  # Rule 2: No references to OTHER project names (cross-contamination)
  for other in "${OTHER_PROJECTS[@]}"; do
    if echo "$rendered" | grep -qF "$other"; then
      log "  - **ERROR**: \`scripts/$script_name\` contains reference to OTHER project \`$other\` — cross-contamination!"
      echo "$rendered" | grep -nF "$other" | head -3 | while IFS= read -r line; do
        log "    $line"
      done
      VALID=false
    fi
  done

  [[ "$VALID" == "true" ]]
}

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
  check-workspace-isolation.sh
  ci-status.sh
  cleanup-worktrees.sh
  clear-inbox.sh
  complete-task.sh
  create-feature-worktrees.sh
  # env.sh intentionally excluded: it contains project-specific config
  # (WORKSPACE_ROOT, NUM_AUTHORS, env sentinel variable) set at project
  # creation time by new-project.sh and must not be overwritten by sync.
  gh-api-read.sh
  global-status.sh
  human-inbox.sh
  migrate-open-prs-v1-to-v2.sh
  node-exec.sh
  post-to-slack.sh
  pr-changed-since-review.sh
  pr-close.sh
  pr-create.sh
  prompts/author.txt
  prompts/lead.txt
  prompts/reviewer.txt
  prune-message-archive.sh
  session-report-draft.sh
  sweep-stale-worktrees.sh
  sync-pr-state.sh
  tmp-clean.sh
  validate-open-prs.sh
  validate-path.sh
  verify-repo-facts.sh
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

  # Substitute [[PROJECT_NAME]] and [[PROJECT_ROOT]] placeholders
  RENDERED="$(sed -e "s/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g" -e "s|\[\[PROJECT_ROOT\]\]|$PROJECT_PATH|g" "$SRC")"

  # Validate the rendered output before writing
  if ! validate_rendered "$script" "$RENDERED"; then
    log "- **SKIPPED**: \`scripts/$script\` — validation failed (see errors above). Fix the template source."
    continue
  fi

  if [[ ! -f "$DST" ]]; then
    mkdir -p "$(dirname "$DST")"
    echo "$RENDERED" > "$DST"
    chmod +x "$DST" 2>/dev/null || true
    log "- **ADDED**: \`scripts/$script\` (new in template)"
  else
    EXISTING="$(cat "$DST")"
    if [[ "$EXISTING" == "$RENDERED" ]]; then
      log "- ok: \`scripts/$script\`"
    else
      log "- **DIFFERS**: \`scripts/$script\` — template has changes; review and apply manually"
      log "  (Run: diff $DST <(sed -e 's/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g' -e 's|\[\[PROJECT_ROOT\]\]|$PROJECT_PATH|g' $SRC))"
    fi
  fi
done

log ""

# ── 2. Root-level scripts ───────────────────────────────────────────────────────
log "## Root scripts"
log ""

ROOT_SCRIPTS=(
  launch-agents.sh
)

for script in "${ROOT_SCRIPTS[@]}"; do
  SRC="$TEMPLATE_ROOT/$script"
  DST="$PROJECT_PATH/$script"

  if [[ ! -f "$SRC" ]]; then
    log "- SKIP: \`$script\` not in template"
    continue
  fi

  RENDERED="$(sed -e "s/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g" -e "s|\[\[PROJECT_ROOT\]\]|$PROJECT_PATH|g" "$SRC")"

  if ! validate_rendered "$script" "$RENDERED"; then
    log "- **SKIPPED**: \`$script\` — validation failed (see errors above). Fix the template source."
    continue
  fi

  if [[ ! -f "$DST" ]]; then
    echo "$RENDERED" > "$DST"
    chmod +x "$DST" 2>/dev/null || true
    log "- **ADDED**: \`$script\` (new in template)"
  else
    EXISTING="$(cat "$DST")"
    if [[ "$EXISTING" == "$RENDERED" ]]; then
      log "- ok: \`$script\`"
    else
      log "- **DIFFERS**: \`$script\` — template has changes; review and apply manually"
      log "  (Run: diff $DST <(sed -e 's/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g' -e 's|\[\[PROJECT_ROOT\]\]|$PROJECT_PATH|g' $SRC))"
    fi
  fi
done

log ""

# ── 3. Settings files ───────────────────────────────────────────────────────────
log "## Settings files"
log ""

SETTINGS_ROLES=(lead-agent author-template reviewer command-center)
for role in "${SETTINGS_ROLES[@]}"; do
  SRC="$TEMPLATE_ROOT/.claude-workspace-template/$role/.claude/settings.local.json"
  DST="$PROJECT_PATH/.claude-workspace/$role/.claude/settings.local.json"

  if [[ ! -f "$SRC" ]]; then
    log "- SKIP: \`$role/.claude/settings.local.json\` not in template"
    continue
  fi

  RENDERED="$(sed -e "s/\[\[PROJECT_NAME\]\]/$PROJECT_NAME/g" -e "s|\[\[PROJECT_ROOT\]\]|$PROJECT_PATH|g" "$SRC")"

  if [[ ! -f "$DST" ]]; then
    mkdir -p "$(dirname "$DST")"
    echo "$RENDERED" > "$DST"
    log "- **ADDED**: \`.claude-workspace/$role/.claude/settings.local.json\` (new in template)"
  else
    EXISTING="$(cat "$DST")"
    if [[ "$EXISTING" == "$RENDERED" ]]; then
      log "- ok: \`.claude-workspace/$role/.claude/settings.local.json\`"
    else
      log "- **DIFFERS**: \`.claude-workspace/$role/.claude/settings.local.json\` — review manually (security-sensitive)"
    fi
  fi
done

log ""

# ── 4. Directories ──────────────────────────────────────────────────────────────
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

# ── 5. CLAUDE.md — manual review checklist ─────────────────────────────────────
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

# ── 6. Template revision tracking ──────────────────────────────────────────────
log "## Template revision"
log ""

TEMPLATE_SHA="$(git -C "$TEMPLATE_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")"
TEMPLATE_BRANCH="$(git -C "$TEMPLATE_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
REVISION_FILE="$PROJECT_PATH/metadata/last-template-sync.md"

printf '# Last template sync\nTimestamp: %s\nTemplate SHA: %s\nTemplate branch: %s\nProject: %s\n' \
  "$TIMESTAMP" "$TEMPLATE_SHA" "$TEMPLATE_BRANCH" "$PROJECT_PATH" > "$REVISION_FILE"

log "- Template SHA: \`$TEMPLATE_SHA\` (branch: $TEMPLATE_BRANCH)"
log "- Written to: \`metadata/last-template-sync.md\`"
log ""

# ── 7. Workspace isolation check ────────────────────────────────────────────────
log "## Isolation check"
log ""

ISOLATION_CHECK="$TEMPLATE_ROOT/scripts/check-workspace-isolation.sh"
if [[ -f "$ISOLATION_CHECK" ]]; then
  ISOLATION_OUTPUT=$("$ISOLATION_CHECK" "$PROJECT_PATH" 2>&1) || true
  while IFS= read -r line; do
    log "$line"
  done <<< "$ISOLATION_OUTPUT"

  if ! "$ISOLATION_CHECK" "$PROJECT_PATH" > /dev/null 2>&1; then
    log ""
    log "**WARNING: isolation check failed — cross-project references detected above.**"
    log "Do NOT commit these files until the contamination is resolved."
  fi
else
  log "- SKIP: \`scripts/check-workspace-isolation.sh\` not found in template"
fi

log ""
log "---"
log "Sync complete. Apply CLAUDE.md changes in the project CC session or via Global CC, then commit."
log ""
log "To commit the mechanical changes applied by this script:"
log "  git -C $PROJECT_PATH add ${ROOT_SCRIPTS[*]} scripts/ metadata/ && git -C $PROJECT_PATH commit -m 'chore: sync from template $TIMESTAMP'"

echo ""
echo "Report written to: $REPORT"

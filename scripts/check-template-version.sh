#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# check-template-version.sh — report drift between this project and the
# llm-wiki template repo. Read-only: applies no changes.
#
# Usage:
#   ./scripts/check-template-version.sh [--template-url=<url>]
#
# Output:
#   - Template HEAD SHA
#   - Last template sync recorded in .llm-wiki-template-log.md (if any)
#   - Per-file status: in sync / out of date / not in template
#   - Suggested next command (update-from-template.sh) if drift exists
#

set -euo pipefail

TEMPLATE_URL="git@github.com:crcresearch/llm-wiki-memory-template.git"

while [[ $# -gt 0 ]]; do
    case $1 in
        --template-url=*) TEMPLATE_URL="${1#*=}"; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Load shared library ---
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

REPO_ROOT=$(lw_repo_root)
# Post-clone authoritative name: the on-disk wiki, not the clone-dir basename
# (F1/F2). Fails loud when the wiki is absent, which is correct for an
# already-instantiated project.
REPO_NAME=$(lw_discover_wiki_name "$REPO_ROOT")
cd "$REPO_ROOT"

# Add the 'template' remote when absent; fail loud if it already points at a
# different repo (F6). Detect the template's default branch (F5).
lw_ensure_remote template "$TEMPLATE_URL"
TEMPLATE_BRANCH=$(lw_default_branch template) || TEMPLATE_BRANCH=main
git fetch --quiet template "$TEMPLATE_BRANCH"
TEMPLATE_REF="template/$TEMPLATE_BRANCH"
TEMPLATE_SHA=$(git rev-parse --short "$TEMPLATE_REF")

# Same file list logic as update-from-template.sh (kept duplicated rather
# than sourced so each script remains standalone).
ALWAYS_FILES=(
    "llm-wiki.md" "wiki/init-wiki.sh" "wiki/agents/README.md"
    "wiki/agents/discipline-gates.md" "wiki/agents/verification-gate.md"
    "wiki/agents/wiki-write-protocol.md"
    "scripts/update-from-template.sh" "scripts/check-template-version.sh"
    "scripts/lib/install-feature.sh"
    "scripts/lib/common.sh" "scripts/lib/report.sh" "scripts/lib/sys.sh"
    "scripts/lib/git.sh" "scripts/lib/identity.sh" "scripts/lib/text.sh"
    "scripts/lib/claude.sh"
    "scripts/enable-feature.sh"
    "scripts/disable-feature.sh" "features/README.md"
    "scripts/wiki-write-protocol/README.md"
    "scripts/wiki-write-protocol/protocol.sh"
    "scripts/wiki-write-protocol/sandbox.sh"
    "scripts/wiki-write-protocol/run-all.sh"
    "scripts/wiki-write-protocol/scenarios/01-different-pages/run.sh"
    "scripts/wiki-write-protocol/scenarios/02-different-sections/run.sh"
    "scripts/wiki-write-protocol/scenarios/03-same-section/run.sh"
    "scripts/wiki-write-protocol/scenarios/04-index-union/run.sh"
    "scripts/wiki-write-protocol/scenarios/05-log-append/run.sh"
    "scripts/wiki-write-protocol/scenarios/06-push-race/run.sh"
    "scripts/wiki-write-protocol/scenarios/07-livelock-retry/run.sh"
    "scripts/wiki-write-protocol/scenarios/08-session-start-auto-pull/run.sh"
    "scripts/wiki-write-protocol/scenarios/09-session-start-divergent/run.sh"
    ".gitignore"
)
# One-shot files (self-delete or consumed at end of bootstrap; not synced).
# Listed for documentation only; see scripts/update-from-template.sh and
# wiki/agents/README.md for the one-shot pattern.
# shellcheck disable=SC2034  # documentation-only; intentionally not iterated
ONE_SHOT_FILES=(
    "scripts/instantiate.sh"
    "CLAUDE.md.template"
    "README.md.template"
    ".claude/settings.json.template"
    ".cursorrules.template"
)
CLAUDE_FILES=(
    ".claude/commands/wiki-experiment.md" ".claude/commands/wiki-source.md"
    ".claude/commands/wiki-lint.md" ".claude/skills/wiki-experiment.md"
    ".claude/skills/wiki-source.md" ".claude/skills/wiki-lint.md"
    "wiki/agents/claude-code/setup.sh" "wiki/agents/claude-code/README.md"
    "wiki/agents/claude-code/templates/claude-md-snippet.md"
    "wiki/agents/claude-code/templates/memory-seed.md"
    "wiki/agents/claude-code/templates/session-start-hook.sh"
)
CURSOR_FILES=(
    ".cursor/rules/wiki-as-memory.mdc" ".cursor/rules/wiki-experiment.mdc"
    ".cursor/rules/wiki-source.mdc" ".cursor/rules/wiki-lint.mdc"
    "wiki/agents/cursor/setup.sh" "wiki/agents/cursor/README.md"
)
SUBSTITUTE_FILES=(
    ".claude/commands/wiki-experiment.md" ".claude/commands/wiki-source.md"
    ".claude/commands/wiki-lint.md" ".claude/skills/wiki-experiment.md"
    ".claude/skills/wiki-source.md" ".claude/skills/wiki-lint.md"
    ".cursor/rules/wiki-as-memory.mdc" ".cursor/rules/wiki-experiment.mdc"
    ".cursor/rules/wiki-source.mdc" ".cursor/rules/wiki-lint.mdc"
)

needs_substitution() {
    local f="$1"
    for s in "${SUBSTITUTE_FILES[@]}"; do
        [[ "$f" == "$s" ]] && return 0
    done
    return 1
}

FILES=("${ALWAYS_FILES[@]}")
HAS_CLAUDE=false
HAS_CURSOR=false
if [[ -d "$REPO_ROOT/.claude" ]] || [[ -d "$REPO_ROOT/wiki/agents/claude-code" ]]; then
    HAS_CLAUDE=true; FILES+=("${CLAUDE_FILES[@]}")
fi
if [[ -d "$REPO_ROOT/.cursor" ]] || [[ -d "$REPO_ROOT/wiki/agents/cursor" ]]; then
    HAS_CURSOR=true; FILES+=("${CURSOR_FILES[@]}")
fi

IN_SYNC=()
OUT_OF_DATE=()
NOT_IN_TEMPLATE=()
LOCAL_MISSING=()

for f in "${FILES[@]}"; do
    if ! git cat-file -e "$TEMPLATE_REF:$f" 2>/dev/null; then
        NOT_IN_TEMPLATE+=("$f"); continue
    fi
    # Materialize via temp file so the trailing newline survives the hash.
    TEMPLATE_TMP=$(mktemp)
    git show "$TEMPLATE_REF:$f" > "$TEMPLATE_TMP"
    if needs_substitution "$f"; then
        sed -i.bak "s|{{REPO_NAME}}|$REPO_NAME|g" "$TEMPLATE_TMP"
        rm -f "${TEMPLATE_TMP}.bak"
    fi
    TEMPLATE_HASH=$(lw_sha256 "$TEMPLATE_TMP")
    rm -f "$TEMPLATE_TMP"

    if [[ ! -f "$f" ]]; then
        LOCAL_MISSING+=("$f"); continue
    fi
    LOCAL_HASH=$(lw_sha256 "$f")
    if [[ "$LOCAL_HASH" == "$TEMPLATE_HASH" ]]; then
        IN_SYNC+=("$f")
    else
        OUT_OF_DATE+=("$f")
    fi
done

# --- Report ---
echo ""
echo "================ check-template-version ================"
echo "Repo:     $REPO_ROOT ($REPO_NAME)"
echo "Template: $TEMPLATE_URL @ $TEMPLATE_SHA"
echo "Overlays present:  claude-code=$HAS_CLAUDE  cursor=$HAS_CURSOR"

# Last sync (from log)
LOG_FILE="$REPO_ROOT/.llm-wiki-template-log.md"
if [[ -f "$LOG_FILE" ]]; then
    LAST=$(grep -E '^## \[' "$LOG_FILE" | tail -1)
    echo "Last sync:   $LAST"
else
    echo "Last sync:   <no .llm-wiki-template-log.md found>"
fi
echo "--------------------------------------------------------"
echo "In sync (${#IN_SYNC[@]}):"
if [[ ${#IN_SYNC[@]} -gt 0 ]]; then
    for f in "${IN_SYNC[@]}"; do echo "  = $f"; done
fi
echo ""
echo "Out of date (${#OUT_OF_DATE[@]}):"
if [[ ${#OUT_OF_DATE[@]} -gt 0 ]]; then
    for f in "${OUT_OF_DATE[@]}"; do echo "  ! $f"; done
fi
if [[ ${#LOCAL_MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "Missing locally (${#LOCAL_MISSING[@]}):"
    for f in "${LOCAL_MISSING[@]}"; do echo "  ? $f"; done
fi
if [[ ${#NOT_IN_TEMPLATE[@]} -gt 0 ]]; then
    echo ""
    echo "Not in template (${#NOT_IN_TEMPLATE[@]}):"
    for f in "${NOT_IN_TEMPLATE[@]}"; do echo "  - $f"; done
fi
echo "========================================================"
echo ""

if [[ ${#OUT_OF_DATE[@]} -gt 0 ]] || [[ ${#LOCAL_MISSING[@]} -gt 0 ]]; then
    echo "Drift detected. To preview a sync:"
    echo "  ./scripts/update-from-template.sh --dry-run"
    echo "To apply:"
    echo "  ./scripts/update-from-template.sh"
    exit 1
fi

echo "All tracked files in sync with template @ $TEMPLATE_SHA."

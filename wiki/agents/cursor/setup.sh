#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# setup.sh — Cursor overlay on top of an llm-wiki project.
#
# This script is the Cursor-specific layer of the llm-wiki pattern, parallel
# to wiki/agents/claude-code/setup.sh. wiki/init-wiki.sh stays agent-agnostic.
#
# Usage:
#   ./wiki/agents/cursor/setup.sh                 # base: verify rules and CLAUDE.md patch
#   ./wiki/agents/cursor/setup.sh --legacy        # also install legacy .cursorrules
#                                                 # (for Cursor builds that don't read .mdc rules)
#
# What it does:
#   Base mode:
#     1. Verifies the wiki is present (else points to init-wiki.sh).
#     2. Patches CLAUDE.md with the "Memory boundary" and "Wiki maintenance
#        behavior" subsections, if not already present. Same markers as the
#        Claude Code overlay; if both overlays are active, only the first one
#        to run patches each subsection.
#     3. Reports presence/absence of .cursor/rules/wiki-*.mdc. These ship
#        with the repository and the script only verifies them.
#
#   --legacy:
#     4. Copies .cursorrules.template -> .cursorrules at the repo root,
#        substituting {{REPO_NAME}}. Skipped if .cursorrules already exists.
#
# Cursor has no SessionStart hook equivalent and no per-user memory directory
# managed by the IDE, so the Claude Code overlay's --hook and --seed-memory
# flags have no analog here. The always-applied rule wiki-as-memory.mdc
# carries the same persistent intent.
#
# Does not commit anything. Does not push.
#

set -euo pipefail

WITH_LEGACY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --legacy) WITH_LEGACY=true; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Load shared library ---
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/common.sh
source "$HERE/../../../scripts/lib/common.sh"

# --- Detect project layout ---
REPO_ROOT=$(lw_repo_root)
# This overlay runs post-clone, so the canonical name is already committed
# as wiki/<name>.wiki. Read it from there rather than from the clone
# directory name (a fork or renamed clone makes the basename, and origin,
# wrong here). lw_discover_wiki_name fails loud if the wiki is absent.
REPO_NAME=$(lw_discover_wiki_name "$REPO_ROOT")
WIKI_DIR="$REPO_ROOT/wiki/${REPO_NAME}.wiki"
SCHEMA_FILE="$WIKI_DIR/SCHEMA_${REPO_NAME}.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

RULES_DIR="$REPO_ROOT/.cursor/rules"
CURSORRULES_DEST="$REPO_ROOT/.cursorrules"
CURSORRULES_TEMPLATE="$REPO_ROOT/.cursorrules.template"

# --- Step 1: verify wiki present ---
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "ERROR: wiki not found at $WIKI_DIR" >&2
    echo "       (expected $SCHEMA_FILE)" >&2
    echo "" >&2
    echo "Run wiki/init-wiki.sh first, then re-run this script." >&2
    exit 1
fi

# --- Step 2: patch CLAUDE.md (shared with Claude Code overlay) ---
# The snippet ships with the Claude Code overlay and carries TWO subsections,
# each with an independent idempotency marker:
#   "### Memory boundary"           (PR #28 — Claude-memory vs wiki layout)
#   "### Wiki maintenance behavior" (original)
# Mirrors claude-code/setup.sh: a derived project may have one but not the
# other, so each marker is checked separately and injected when missing.
# Whichever overlay runs first patches; the other then skips.
SNIPPET_FILE="$REPO_ROOT/wiki/agents/claude-code/templates/claude-md-snippet.md"
MARKER_MAINTENANCE="### Wiki maintenance behavior"
MARKER_BOUNDARY="### Memory boundary"

# Extract the whole snippet body once, with comments stripped and
# placeholders substituted.
if [[ -f "$SNIPPET_FILE" ]]; then
    SNIPPET_BODY=$(grep -v '^<!--' "$SNIPPET_FILE" | grep -v '^-->' | sed "s/\${REPO_NAME}/$REPO_NAME/g")
fi

# Extract just the Memory boundary subsection (between its header and the
# next ### header), in case we need to inject it alone.
extract_boundary_only() {
    awk '
        /^### Memory boundary/ { capture = 1 }
        /^### Wiki maintenance behavior/ { capture = 0 }
        capture { print }
    ' <<<"$SNIPPET_BODY"
}

inject_before_kg_or_append() {
    local content="$1"
    local label="$2"
    if grep -qF "### Knowledge Graph" "$CLAUDE_MD"; then
        # lw_insert_before is the shared BSD-safe injector (tempfile +
        # getline, not awk -v). The old inline `awk -v snippet=...` here
        # silently no-opped on BSD awk (macOS); claude-code/setup.sh routes
        # through the same helper so both overlays share one injection path.
        lw_insert_before "$CLAUDE_MD" "### Knowledge Graph" "$content"
        lw_record_change "CLAUDE.md: injected '$label' before '### Knowledge Graph'"
    else
        printf '\n%s\n' "$content" >> "$CLAUDE_MD"
        lw_record_change "CLAUDE.md: appended '$label' at end"
    fi
}

if [[ ! -f "$CLAUDE_MD" ]]; then
    lw_record_skip "CLAUDE.md: not found (skipped). Run instantiate.sh to generate it."
elif [[ ! -f "$SNIPPET_FILE" ]]; then
    lw_record_skip "CLAUDE.md: template snippet not found at $SNIPPET_FILE (skipped)"
else
    HAS_MAINTENANCE=$(grep -qF "$MARKER_MAINTENANCE" "$CLAUDE_MD" && echo true || echo false)
    HAS_BOUNDARY=$(grep -qF "$MARKER_BOUNDARY" "$CLAUDE_MD" && echo true || echo false)

    if ! $HAS_MAINTENANCE; then
        # First-run case: inject the entire snippet (both subsections).
        inject_before_kg_or_append "$SNIPPET_BODY" "Memory boundary + Wiki maintenance behavior"
    elif ! $HAS_BOUNDARY; then
        # Partial-state case: maintenance present from an earlier run,
        # boundary subsection missing (added in PR #28). Inject just the
        # boundary subsection.
        inject_before_kg_or_append "$(extract_boundary_only)" "Memory boundary"
    else
        lw_record_skip "CLAUDE.md: 'Memory boundary' and 'Wiki maintenance behavior' both already present (skipped)"
    fi
fi

# --- Step 3: verify .cursor/rules/wiki-*.mdc present ---
RULES_MISSING=()
for rule in wiki-as-memory wiki-experiment wiki-source wiki-lint; do
    if [[ ! -f "$RULES_DIR/${rule}.mdc" ]]; then
        RULES_MISSING+=("$rule")
    fi
done

if [[ ${#RULES_MISSING[@]} -eq 0 ]]; then
    lw_record_skip ".cursor/rules/: all four present (wiki-as-memory, wiki-experiment, wiki-source, wiki-lint)"
else
    lw_record_skip ".cursor/rules/: MISSING — ${RULES_MISSING[*]} (these should be committed in the repo)"
fi

# --- Step 4: install legacy .cursorrules (--legacy) ---
if $WITH_LEGACY; then
    if [[ -f "$CURSORRULES_DEST" ]]; then
        lw_record_skip ".cursorrules: already present (skipped)"
    elif [[ ! -f "$CURSORRULES_TEMPLATE" ]]; then
        lw_record_skip ".cursorrules: template not found at $CURSORRULES_TEMPLATE (skipped)"
    else
        sed "s/{{REPO_NAME}}/$REPO_NAME/g" "$CURSORRULES_TEMPLATE" > "$CURSORRULES_DEST"
        lw_record_change ".cursorrules: created from template (legacy single-file Cursor format)"
    fi
fi

# --- Summary ---
echo ""
echo "================ Cursor overlay setup ================"
echo "Repo:        $REPO_ROOT"
echo "Wiki:        $WIKI_DIR"
echo "Flags:       --legacy=$WITH_LEGACY"
echo "------------------------------------------------------"
lw_print_report
echo "======================================================"
echo ""

if lw_changed_p; then
    echo "Next steps:"
    echo "  Review the changes above, then stage and commit:"
    echo "    git add CLAUDE.md .cursor/ ${WITH_LEGACY:+.cursorrules}"
    echo "    git commit -m \"cursor: apply Cursor overlay (setup.sh)\""
    echo ""
fi

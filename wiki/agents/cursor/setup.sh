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
# each delimited by a paired sentinel (<!-- lw:memory-boundary -->,
# <!-- lw:wiki-maintenance -->). Idempotency is the opening sentinel, not a
# prose-heading grep (F7). Same path as claude-code/setup.sh, so whichever
# overlay runs first injects and the other skips; a derived project missing one
# subsection still gets it.
SNIPPET_FILE="$REPO_ROOT/wiki/agents/claude-code/templates/claude-md-snippet.md"
KG_ANCHOR="### Knowledge Graph"

# Body of one subsection, read from BETWEEN its sentinel pair in the template
# (so the template's header comment never leaks in), with ${REPO_NAME}
# substituted. lw_inject_block re-wraps this body in the same sentinels.
extract_block() {
    awk -v open="<!-- lw:$1 -->" -v endm="<!-- /lw:$1 -->" '
        $0 == open { grab=1; next }
        $0 == endm { grab=0 }
        grab       { print }
    ' "$SNIPPET_FILE" | sed "s/\${REPO_NAME}/$REPO_NAME/g"
}

if [[ ! -f "$CLAUDE_MD" ]]; then
    lw_record_skip "CLAUDE.md: not found (skipped). Run instantiate.sh to generate it."
elif [[ ! -f "$SNIPPET_FILE" ]]; then
    lw_record_skip "CLAUDE.md: template snippet not found at $SNIPPET_FILE (skipped)"
else
    patched=false
    # Migrate any pre-sentinel prose sections in place first (wrap, preserving
    # local edits), so the sentinel-based injection below does not duplicate.
    if lw_wrap_section "$CLAUDE_MD" memory-boundary "### Memory boundary"; then
        lw_record_change "CLAUDE.md: migrated legacy 'Memory boundary' section to sentinels"; patched=true
    fi
    if lw_wrap_section "$CLAUDE_MD" wiki-maintenance "### Wiki maintenance behavior"; then
        lw_record_change "CLAUDE.md: migrated legacy 'Wiki maintenance behavior' section to sentinels"; patched=true
    fi

    # memory-boundary precedes wiki-maintenance; anchor on the latter's
    # sentinel when present, else the Knowledge Graph subsection.
    MB_ANCHOR="$KG_ANCHOR"
    grep -qF '<!-- lw:wiki-maintenance -->' "$CLAUDE_MD" 2>/dev/null && MB_ANCHOR='<!-- lw:wiki-maintenance -->'
    if lw_inject_block "$CLAUDE_MD" memory-boundary "$(extract_block memory-boundary)" "$MB_ANCHOR"; then
        lw_record_change "CLAUDE.md: injected 'Memory boundary' subsection"; patched=true
    fi
    if lw_inject_block "$CLAUDE_MD" wiki-maintenance "$(extract_block wiki-maintenance)" "$KG_ANCHOR"; then
        lw_record_change "CLAUDE.md: injected 'Wiki maintenance behavior' subsection"; patched=true
    fi
    $patched || lw_record_skip "CLAUDE.md: 'Memory boundary' and 'Wiki maintenance behavior' both already present (skipped)"
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

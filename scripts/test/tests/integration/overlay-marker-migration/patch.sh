#!/usr/bin/env bash
# Patch: fixture for the CLAUDE.md marker-format migration (chunk 05, F7),
# now cursor-only. The claude-code overlay no longer touches CLAUDE.md
# (its instructions ship as .claude/rules/*.md), so only the cursor
# overlay still carries the sentinel-wrap migration shim.
#
# Projects created before the sentinel format carry bare "### Heading"
# subsections. cursor/setup.sh must wrap those in paired <!-- lw:... -->
# sentinels in place (preserving local edits) so its sentinel-based
# injection stays idempotent and never duplicates a section.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/overlay-marker-migration/ with:
#     cur-both/     both legacy prose subsections + a Knowledge Graph
#                   anchor, each with a unique local edit (to prove
#                   preservation); drives wiki/agents/cursor/setup.sh

set -uo pipefail

STAGE="$SANDBOX/overlay-marker-migration"
mkdir -p "$STAGE"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
TPL_SRC="$REPO_ROOT/wiki/agents/claude-code/templates"

# $1=project dir, $2=wiki name
_mkproj() {
    local dir="$1" wn="$2"
    git init -q "$dir"
    git -C "$dir" config user.email "mig-test@example.test"
    git -C "$dir" config user.name  "mig test"
    # cursor/setup.sh reads its SNIPPET_FILE from the claude-code overlay's
    # templates dir inside the project root, so stage a copy.
    mkdir -p "$dir/wiki/agents/claude-code"
    cp -R "$TPL_SRC" "$dir/wiki/agents/claude-code/templates"
    mkdir -p "$dir/wiki/$wn.wiki"
    : > "$dir/wiki/$wn.wiki/SCHEMA_$wn.md"
}

# Legacy prose subsections (no sentinels), as instantiate.sh rendered them
# before the sentinel format. Unique tokens mark local edits we must preserve.
_legacy_both() {
    cat <<'EOF'
# Project

## Wiki

Wiki intro.

### Memory boundary

Boundary body. LOCAL_EDIT_BOUNDARY_XYZ

### Wiki maintenance behavior

Maintenance body. LOCAL_EDIT_MAINT_ABC

### Knowledge Graph

KG section.
EOF
}

# The cursor leg drives wiki/agents/cursor/setup.sh from the checkout,
# which instantiate prunes in claude-code-derived projects. Stage it only
# when the overlay exists; assertions.sh skips when cur-both is absent.
if [ -f "$REPO_ROOT/wiki/agents/cursor/setup.sh" ]; then
    _mkproj "$STAGE/cur-both" glyph
    _legacy_both > "$STAGE/cur-both/CLAUDE.md"
    # cursor overlay keys off .cursor/rules presence in some flows; not required
    # here (setup.sh patches CLAUDE.md regardless), but mark the overlay active.
    mkdir -p "$STAGE/cur-both/.cursor/rules"
fi

echo "  overlay-marker-migration patch applied: fixtures at $STAGE"

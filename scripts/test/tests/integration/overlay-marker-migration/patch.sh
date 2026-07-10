#!/usr/bin/env bash
# Patch: fixtures for the CLAUDE.md marker-format migration (chunk 05, F7).
#
# Projects created before the sentinel format carry bare "### Heading"
# subsections. setup.sh must wrap those in paired <!-- lw:... --> sentinels
# in place (preserving local edits) so its sentinel-based injection stays
# idempotent and never duplicates a section.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/overlay-marker-migration/ with project fixtures,
#   each a git repo carrying the claude-code overlay templates and a wiki:
#     old-both/     both legacy prose subsections + a Knowledge Graph anchor,
#                   each with a unique local edit (to prove preservation)
#     old-partial/  only the legacy "Wiki maintenance behavior" subsection
#                   (the pre-boundary install state); memory-boundary is absent
#     old-no-kg/    both legacy subsections, NO Knowledge Graph anchor, so the
#                   wiki-maintenance section runs to EOF (the real dev-self shape)
#     cur-both/     same as old-both, used to drive the cursor overlay through
#                   the shared injection path

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

_mkproj "$STAGE/old-both" sigil
_legacy_both > "$STAGE/old-both/CLAUDE.md"

# The cursor leg drives wiki/agents/cursor/setup.sh from the checkout,
# which instantiate prunes in claude-code-derived projects. Stage it only
# when the overlay exists; assertions.sh skips the cursor asserts when
# cur-both is absent.
if [ -f "$REPO_ROOT/wiki/agents/cursor/setup.sh" ]; then
    _mkproj "$STAGE/cur-both" glyph
    _legacy_both > "$STAGE/cur-both/CLAUDE.md"
    # cursor overlay keys off .cursor/rules presence in some flows; not required
    # here (setup.sh patches CLAUDE.md regardless), but mark the overlay active.
    mkdir -p "$STAGE/cur-both/.cursor/rules"
fi

_mkproj "$STAGE/old-partial" sigil
cat > "$STAGE/old-partial/CLAUDE.md" <<'EOF'
# Project

## Wiki

Wiki intro.

### Wiki maintenance behavior

Maintenance body. LOCAL_EDIT_MAINT_ABC

### Knowledge Graph

KG section.
EOF

_mkproj "$STAGE/old-no-kg" sigil
cat > "$STAGE/old-no-kg/CLAUDE.md" <<'EOF'
# Project

## Wiki

Wiki intro.

### Memory boundary

Boundary body. LOCAL_EDIT_BOUNDARY_XYZ

### Wiki maintenance behavior

Maintenance body. LOCAL_EDIT_MAINT_ABC
EOF

echo "  overlay-marker-migration patch applied: fixtures at $STAGE"

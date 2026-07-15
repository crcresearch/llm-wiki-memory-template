#!/usr/bin/env bash
# Assertions: run the real cursor overlay setup.sh against a legacy-marker
# fixture and verify the chunk-05 marker migration (F7), cursor-only now
# that the claude-code overlay no longer touches CLAUDE.md:
#   - legacy prose sections are wrapped in paired sentinels in place;
#   - no section is duplicated (the sentinel shim is load-bearing);
#   - local edits inside a section are preserved (D4: wrap, not replace);
#   - a re-run is byte-for-byte idempotent.
#
# setup.sh takes the project root from the current directory, so the run
# cds into the fixture.

STAGE="$SANDBOX/overlay-marker-migration"
REPO_ROOT_MM="$(cd "$HERE/../.." && pwd)"
CU_SETUP="$REPO_ROOT_MM/wiki/agents/cursor/setup.sh"

count() { grep -cE "$1" "$2" 2>/dev/null || true; }

# patch.sh stages cur-both only when the checkout ships the cursor overlay
# (instantiate prunes it in claude-code-derived projects).
if [ ! -d "$STAGE/cur-both" ]; then
    skip "overlay-marker-migration" "cursor overlay not in this checkout (pruned in derived projects)"
    return 0 2>/dev/null || true
fi

CB="$STAGE/cur-both/CLAUDE.md"
( cd "$STAGE/cur-both" && bash "$CU_SETUP" ) >/dev/null 2>&1
assert "cursor: memory-boundary opening sentinel present" \
    "grep -qF '<!-- lw:memory-boundary -->' '$CB'"
assert "cursor: memory-boundary closing sentinel present" \
    "grep -qF '<!-- /lw:memory-boundary -->' '$CB'"
assert "cursor: wiki-maintenance opening sentinel present" \
    "grep -qF '<!-- lw:wiki-maintenance -->' '$CB'"
assert "cursor: wiki-maintenance closing sentinel present" \
    "grep -qF '<!-- /lw:wiki-maintenance -->' '$CB'"
assert_eq "cursor: exactly one '### Memory boundary' (no duplicate)" "1" \
    "$(count '^### Memory boundary$' "$CB")"
assert_eq "cursor: exactly one '### Wiki maintenance behavior' (no duplicate)" "1" \
    "$(count '^### Wiki maintenance behavior$' "$CB")"
assert "cursor: local edit inside memory-boundary preserved" \
    "grep -qF 'LOCAL_EDIT_BOUNDARY_XYZ' '$CB'"
assert "cursor: local edit inside wiki-maintenance preserved" \
    "grep -qF 'LOCAL_EDIT_MAINT_ABC' '$CB'"
assert "cursor: Knowledge Graph anchor preserved" \
    "grep -qxF '### Knowledge Graph' '$CB'"

# Idempotency: a second run changes nothing.
cp "$CB" "$CB.snap"
( cd "$STAGE/cur-both" && bash "$CU_SETUP" ) >/dev/null 2>&1
assert "cursor: re-run is byte-for-byte idempotent" "diff -q '$CB.snap' '$CB'"

#!/usr/bin/env bash
# Assertions: run the real overlay setup.sh scripts against legacy-marker
# fixtures and verify the chunk-05 marker migration (F7):
#   - legacy prose sections are wrapped in paired sentinels in place;
#   - no section is duplicated (the sentinel shim is load-bearing);
#   - local edits inside a section are preserved (D4: wrap, not replace);
#   - a partial install (one subsection) upgrades to both;
#   - a section with no Knowledge Graph anchor (runs to EOF) still wraps;
#   - the cursor overlay migrates via the same shared path;
#   - a re-run is byte-for-byte idempotent.
#
# setup.sh takes the project root from the current directory, so each run cds
# into a fixture.

STAGE="$SANDBOX/overlay-marker-migration"
REPO_ROOT_MM="$(cd "$HERE/../.." && pwd)"
CC_SETUP="$REPO_ROOT_MM/wiki/agents/claude-code/setup.sh"
CU_SETUP="$REPO_ROOT_MM/wiki/agents/cursor/setup.sh"

count() { grep -cE "$1" "$2" 2>/dev/null || true; }

# --- old-both: both legacy subsections wrap, no duplicates, edits preserved ---
OB="$STAGE/old-both/CLAUDE.md"
( cd "$STAGE/old-both" && CLAUDE_CONFIG_DIR="$STAGE" bash "$CC_SETUP" ) >/dev/null 2>&1
assert "old-both: memory-boundary opening sentinel present" \
    "grep -qF '<!-- lw:memory-boundary -->' '$OB'"
assert "old-both: memory-boundary closing sentinel present" \
    "grep -qF '<!-- /lw:memory-boundary -->' '$OB'"
assert "old-both: wiki-maintenance opening sentinel present" \
    "grep -qF '<!-- lw:wiki-maintenance -->' '$OB'"
assert "old-both: wiki-maintenance closing sentinel present" \
    "grep -qF '<!-- /lw:wiki-maintenance -->' '$OB'"
assert_eq "old-both: exactly one '### Memory boundary' (no duplicate)" "1" \
    "$(count '^### Memory boundary$' "$OB")"
assert_eq "old-both: exactly one '### Wiki maintenance behavior' (no duplicate)" "1" \
    "$(count '^### Wiki maintenance behavior$' "$OB")"
assert "old-both: local edit inside memory-boundary preserved" \
    "grep -qF 'LOCAL_EDIT_BOUNDARY_XYZ' '$OB'"
assert "old-both: local edit inside wiki-maintenance preserved" \
    "grep -qF 'LOCAL_EDIT_MAINT_ABC' '$OB'"
assert "old-both: Knowledge Graph anchor preserved" \
    "grep -qxF '### Knowledge Graph' '$OB'"

# Idempotency: a second run changes nothing.
cp "$OB" "$OB.snap"
( cd "$STAGE/old-both" && CLAUDE_CONFIG_DIR="$STAGE" bash "$CC_SETUP" ) >/dev/null 2>&1
assert "old-both: re-run is byte-for-byte idempotent" "diff -q '$OB.snap' '$OB'"

# --- old-partial: only wiki-maintenance present -> both end up present, once ---
OP="$STAGE/old-partial/CLAUDE.md"
( cd "$STAGE/old-partial" && CLAUDE_CONFIG_DIR="$STAGE" bash "$CC_SETUP" ) >/dev/null 2>&1
assert "old-partial: wiki-maintenance sentinel present" \
    "grep -qF '<!-- lw:wiki-maintenance -->' '$OP'"
assert "old-partial: memory-boundary sentinel present (injected fresh)" \
    "grep -qF '<!-- lw:memory-boundary -->' '$OP'"
assert_eq "old-partial: exactly one '### Wiki maintenance behavior'" "1" \
    "$(count '^### Wiki maintenance behavior$' "$OP")"
assert_eq "old-partial: exactly one '### Memory boundary'" "1" \
    "$(count '^### Memory boundary$' "$OP")"
assert "old-partial: pre-existing local edit preserved" \
    "grep -qF 'LOCAL_EDIT_MAINT_ABC' '$OP'"

# --- old-no-kg: section runs to EOF, still wraps with a closing sentinel ---
ON="$STAGE/old-no-kg/CLAUDE.md"
( cd "$STAGE/old-no-kg" && CLAUDE_CONFIG_DIR="$STAGE" bash "$CC_SETUP" ) >/dev/null 2>&1
assert "old-no-kg: wiki-maintenance closing sentinel present (EOF boundary)" \
    "grep -qF '<!-- /lw:wiki-maintenance -->' '$ON'"
assert_eq "old-no-kg: exactly one '### Wiki maintenance behavior'" "1" \
    "$(count '^### Wiki maintenance behavior$' "$ON")"
assert "old-no-kg: local edits preserved" \
    "grep -qF 'LOCAL_EDIT_MAINT_ABC' '$ON'"

# --- cursor overlay migrates via the same shared path ---
# patch.sh stages cur-both only when the checkout ships the cursor overlay
# (instantiate prunes it in claude-code-derived projects).
if [ ! -d "$STAGE/cur-both" ]; then
    skip "overlay-marker-migration cursor leg" "cursor overlay not in this checkout (pruned in derived projects)"
else
    CB="$STAGE/cur-both/CLAUDE.md"
    ( cd "$STAGE/cur-both" && bash "$CU_SETUP" ) >/dev/null 2>&1
    assert "cursor: legacy section wrapped in sentinels" \
        "grep -qF '<!-- lw:wiki-maintenance -->' '$CB'"
    assert_eq "cursor: exactly one '### Memory boundary' (no duplicate)" "1" \
        "$(count '^### Memory boundary$' "$CB")"
fi

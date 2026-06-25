#!/usr/bin/env bash
# Assertions: adopt.sh --apply Phase 2A applies append-only TOUCH to
# .gitignore via lw_inject_block; classifies managed-block and merge
# grants but defers them; manifest records each TOUCH apply.

STAGE="$SANDBOX/adopt-apply-touch"
HOST="$STAGE/host"
OUT1="$STAGE/apply-run1.txt"
OUT2="$STAGE/apply-run2.txt"

# --- First run produced output ---
assert "first --apply produced output" "[ -f '$OUT1' ]"

# --- .gitignore was append-only touched (sentinel-paired block at end) ---
assert "host .gitignore now contains the opening lw:wiki-rules sentinel" \
    "grep -qF '<!-- lw:wiki-rules -->' '$HOST/.gitignore'"
assert "host .gitignore contains the closing lw:wiki-rules sentinel" \
    "grep -qF '<!-- /lw:wiki-rules -->' '$HOST/.gitignore'"
assert "host .gitignore now contains the canonical wiki/*.wiki/ rule" \
    "grep -qFx 'wiki/*.wiki/' '$HOST/.gitignore'"

# --- Host's prior .gitignore content survived above the new block ---
assert "host's '*.pyc' rule preserved" \
    "grep -qFx '*.pyc' '$HOST/.gitignore'"
assert "host's '__pycache__/' rule preserved" \
    "grep -qFx '__pycache__/' '$HOST/.gitignore'"
assert "host's '.env' rule preserved" \
    "grep -qFx '.env' '$HOST/.gitignore'"

# --- Manifest records the apply outcomes ---
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest lists .gitignore TOUCH as applied (first run)" \
    "grep -qF '.gitignore (append-only): applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports CLAUDE.md managed-block as deferred to Phase 2B" \
    "grep -qF 'CLAUDE.md (managed-block): deferred' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports settings.json merge as deferred to Phase 3" \
    "grep -qF '.claude/settings.json (merge): deferred' '$HOST/.llm-wiki-adopt-log.md'"

# --- Host's prose (CLAUDE.md, README.md) untouched in this phase ---
assert "host CLAUDE.md preserved (managed-block deferred, did not inject)" \
    "grep -qF 'Host-authored project guidance' '$HOST/CLAUDE.md'"
assert "host CLAUDE.md has NO lw:wiki-section sentinel yet (Phase 2B job)" \
    "! grep -qF '<!-- lw:wiki-section -->' '$HOST/CLAUDE.md'"
assert "host README preserved" \
    "grep -qF 'Host-authored README' '$HOST/README.md'"

# --- Second run: idempotency check on lw_inject_block ---
assert "second --apply produced output" "[ -f '$OUT2' ]"
sentinel_count=$(grep -cF '<!-- lw:wiki-rules -->' "$HOST/.gitignore" || true)
assert "opening sentinel appears exactly once after two --apply runs" \
    "[ '$sentinel_count' -eq 1 ]"
assert "manifest lists .gitignore TOUCH as already-present (second run)" \
    "grep -qF '.gitignore (append-only): already-present' '$HOST/.llm-wiki-adopt-log.md'"

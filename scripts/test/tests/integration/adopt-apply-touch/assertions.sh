#!/usr/bin/env bash
# Assertions: adopt.sh --apply applies the managed-block and merge TOUCH
# grants via the overlay setup.sh; the host's .gitignore is never
# modified (the wiki ignore rule arrives as the ADDed wiki/.gitignore);
# manifest records each TOUCH apply.

STAGE="$SANDBOX/adopt-apply-touch"
HOST="$STAGE/host"
OUT1="$STAGE/apply-run1.txt"
OUT2="$STAGE/apply-run2.txt"

# --- First run produced output ---
assert "first --apply produced output" "[ -f '$OUT1' ]"

# --- Host .gitignore untouched; wiki ignore rule arrived via ADD ---
assert "host .gitignore is byte-identical to its pre-adopt snapshot" \
    "cmp -s '$STAGE/gitignore.before' '$HOST/.gitignore'"
assert "wiki/.gitignore was ADDed to the host" \
    "[ -f '$HOST/wiki/.gitignore' ]"
assert "wiki/.gitignore carries the *.wiki/ rule" \
    "grep -qFx '*.wiki/' '$HOST/wiki/.gitignore'"
assert "git ignores the wiki sub-repo via wiki/.gitignore" \
    "git -C '$HOST' check-ignore -q wiki/touch-host.wiki/"

# --- Manifest records the apply outcomes ---
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest does NOT list a .gitignore TOUCH (no such grant anymore)" \
    "! grep -qF -- '- .gitignore (' '$HOST/.llm-wiki-adopt-log.md'"
# Phase 2B: managed-block now delegates to overlay setup.sh. With the
# claude-code overlay copied via ADD and init-wiki creating the wiki
# sub-repo, the overlay setup runs successfully and the manifest records
# the managed-block TOUCH as applied via the overlay rather than deferred.
assert "manifest reports CLAUDE.md managed-block as applied via overlay setup.sh" \
    "grep -qF 'CLAUDE.md (managed-block): applied via wiki/agents/claude-code/setup.sh' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports settings.json merge as applied via setup.sh --hook" \
    "grep -qF '.claude/settings.json (merge): applied via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md'"
# Guard against the false-positive that the previous version of this test
# allowed: a 'failed' entry in any manifest run would prove the assertion
# above is insufficient on its own (the grep only requires the 'applied'
# string to appear once across the whole manifest).
assert "manifest does NOT report settings.json merge as failed in any run" \
    "! grep -qF '.claude/settings.json (merge): failed' '$HOST/.llm-wiki-adopt-log.md'"

# --- Phase 3: settings.json now has the SessionStart hook (via jq merge) ---
assert "host .claude/settings.json now references session-start.sh" \
    "grep -qF 'session-start.sh' '$HOST/.claude/settings.json'"
assert "host's own 'permissions.allow.Bash' key survived the merge" \
    "grep -qF 'Bash' '$HOST/.claude/settings.json'"

# --- Phase 2B: init-wiki + overlay setup status in manifest ---
assert "manifest records init-wiki as applied on first run" \
    "grep -qF -- '- init-wiki: applied' '$STAGE/apply-run1.txt' || \\
     grep -qF -- '- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records init-wiki as already-present on second run" \
    "grep -qF -- '- init-wiki: already-present' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records overlay setup status as applied" \
    "grep -qF -- '- overlay setup: applied' '$HOST/.llm-wiki-adopt-log.md'"

# --- Phase 2B: wiki sub-repo created in host ---
assert "wiki sub-repo created at wiki/touch-host.wiki/" \
    "[ -d '$HOST/wiki/touch-host.wiki/.git' ]"

# --- Phase 2B: CLAUDE.md now has overlay-injected sentinels ---
assert "host CLAUDE.md now has lw:memory-boundary sentinel (injected by overlay setup)" \
    "grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md'"
assert "host CLAUDE.md now has lw:wiki-maintenance sentinel" \
    "grep -qF '<!-- lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"

# --- Host's prose (CLAUDE.md, README.md) untouched in this phase ---
assert "host CLAUDE.md prose preserved above injected blocks" \
    "grep -qF 'Host-authored project guidance' '$HOST/CLAUDE.md'"
assert "host README preserved" \
    "grep -qF 'Host-authored README' '$HOST/README.md'"

# --- Second run: idempotency ---
assert "second --apply produced output" "[ -f '$OUT2' ]"
assert "host .gitignore still byte-identical after the second --apply" \
    "cmp -s '$STAGE/gitignore.before' '$HOST/.gitignore'"
mb_sentinel_count=$(grep -cF '<!-- lw:memory-boundary -->' "$HOST/CLAUDE.md" || true)
assert "CLAUDE.md memory-boundary sentinel appears exactly once after two --apply runs" \
    "[ '$mb_sentinel_count' -eq 1 ]"

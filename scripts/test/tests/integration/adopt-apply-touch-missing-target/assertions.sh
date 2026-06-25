#!/usr/bin/env bash
# Assertions: when a granted target is absent on disk, adopt classifies
# the grant as TOUCH_MISSING. The grant must surface in GRANT WARNINGS
# (so the user sees it), must NOT appear in TOUCH applied (no payload
# delivered), and the absent file must NOT be silently created. The
# CLAUDE.md grant in this fixture targets a real file and exists only
# to anchor a fully-completing Phase 2B (so we can also assert manifest
# write); CLAUDE.md is NOT the subject of these assertions.

STAGE="$SANDBOX/adopt-apply-touch-missing-target"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"

# The MISSING target surfaces in GRANT WARNINGS with the right reason.
assert "GRANT WARNINGS section lists .claude/settings.json as moot (absent in host)" \
    "grep -qF '? .claude/settings.json  (granted but absent in host' '$OUT'"

# It does NOT appear in TOUCH applied.
assert "TOUCH block does NOT list .claude/settings.json" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.claude/settings.json'"

# CLAUDE.md is the anchor grant -- it should NOT be in GRANT WARNINGS
# (host has it; so it classifies as TOUCH, not MISSING).
assert "GRANT WARNINGS does NOT list CLAUDE.md (host has it; classifies as TOUCH)" \
    "! awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md'"

# Adopt did NOT silently create .claude/settings.json (the absent file
# stays absent; the grant is moot, not fulfilled).
assert "adopt did NOT create .claude/settings.json (absent grant stays absent)" \
    "[ ! -f '$HOST/.claude/settings.json' ]"
assert "adopt did NOT create the .claude/ directory" \
    "[ ! -d '$HOST/.claude' ]"

# adopt --apply completed end-to-end (manifest written).
assert "manifest exists (adopt --apply completed)" \
    "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"

# The manifest does NOT report a settings.json TOUCH entry (the grant
# never produced one because the target was MISSING).
assert "manifest does NOT list .claude/settings.json (merge):" \
    "! grep -qF '.claude/settings.json (merge):' '$HOST/.llm-wiki-adopt-log.md'"

#!/usr/bin/env bash
# Assertions: granted targets that don't exist on disk classify as
# 'granted but absent in host' (TOUCH_MISSING) and surface in
# GRANT WARNINGS, not in TOUCH applied. Adopt does NOT create the
# files; it leaves the absence to the host's decision.

STAGE="$SANDBOX/adopt-apply-touch-missing-target"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"

# Both granted targets are absent in host -> they appear in GRANT WARNINGS.
assert "GRANT WARNINGS section names CLAUDE.md as moot (absent in host)" \
    "awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md' && \\
     awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF 'absent in host'"
assert "GRANT WARNINGS names .claude/settings.json as moot" \
    "awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qF '.claude/settings.json'"

# Neither target ends up in TOUCH applied.
assert "TOUCH block does NOT list CLAUDE.md" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md'"
assert "TOUCH block does NOT list .claude/settings.json" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.claude/settings.json'"

# The grant for CLAUDE.md must NOT drive a TOUCH. init-wiki (Phase 2B)
# has its own path that seeds CLAUDE.md when absent, with the sentinels
# already in the seed template -- the seed alone is not evidence the
# grant drove anything. The discriminators are:
#  - the apply output's TOUCH block lists 0 files (already asserted above),
#  - the manifest does NOT list 'CLAUDE.md (managed-block):' (below),
#  - .claude/settings.json (no init-wiki seed path for it) is not created.
assert "adopt did NOT create .claude/settings.json (no init-wiki path for it)" \
    "[ ! -f '$HOST/.claude/settings.json' ]"
assert "apply summary reports 0 TOUCH files" \
    "grep -qE 'TOUCH \\(host-owned, granted +-- +0 files\\)' '$OUT' || \\
     grep -qE 'TOUCH .*0 files' '$OUT'"

# But Phase 2B overlay setup still runs (host has the overlay setup.sh).
# When CLAUDE.md is missing, the overlay setup either skips that step or
# fails the CLAUDE.md injection part. Either way the manifest should
# capture the outcome honestly without crashing.
assert "manifest exists (script did not crash)" \
    "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"

# The TOUCH applied section in the manifest does NOT have a managed-block
# entry for CLAUDE.md because the grant was MISSING, not TOUCH.
assert "manifest does NOT list CLAUDE.md (managed-block):" \
    "! grep -qF 'CLAUDE.md (managed-block):' '$HOST/.llm-wiki-adopt-log.md'"

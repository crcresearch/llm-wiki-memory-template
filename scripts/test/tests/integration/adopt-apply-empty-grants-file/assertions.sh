#!/usr/bin/env bash
# Assertions: an explicit empty grants file is the host's opt-out from
# the defaults. Adopt must read the file, classify zero grants, and
# leave the three default targets untouched by the TOUCH dispatch.
# Note: CLAUDE.md still receives the overlay setup's unconditional
# sentinel injection in Phase 2B (since --agent=claude-code), so its
# presence on disk is NOT a discriminator. Discriminator is the
# absence of the .gitignore wiki rule and the absence of
# .claude/settings.json (those two paths are TOUCH-gated).

STAGE="$SANDBOX/adopt-apply-empty-grants-file"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"

# Header reports the file as the source, not defaults.
assert "header reports grants source as a file (not defaults)" \
    "grep -qE 'Grants file:\\s+.llm-wiki-adopt-grants.yml \\(0 grant\\(s\\) found\\)' '$OUT'"
assert "header does NOT report 'defaults'" \
    "! grep -qF 'Grants file:      defaults' '$OUT'"

# TOUCH section is empty (no defaults overlaid on an explicit empty file).
assert "TOUCH section reports 0 files (explicit opt-out honoured)" \
    "grep -qF 'TOUCH (host-owned, granted' '$OUT' && \\
     grep -qF '0 files)' '$OUT'"

# Phase 2A append-only path did NOT fire on .gitignore.
assert ".gitignore was NOT augmented with the wiki/*.wiki/ rule" \
    "! grep -qF 'wiki/*.wiki/' '$HOST/.gitignore'"
assert ".gitignore preserved host's prior '*.pyc' rule" \
    "grep -qFx '*.pyc' '$HOST/.gitignore'"

# Phase 3 merge path did NOT fire on .claude/settings.json.
assert ".claude/settings.json was NOT created" \
    "[ ! -f '$HOST/.claude/settings.json' ]"

# Manifest reports zero TOUCH applied.
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest reports TOUCH applied count of 0" \
    "grep -qE '^- TOUCH applied \\(0\\)' '$HOST/.llm-wiki-adopt-log.md'"

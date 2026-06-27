#!/usr/bin/env bash
# Assertions: a malformed grants YAML should not crash the parser. The
# minimal awk reader in adopt.sh picks up valid lines and silently
# skips garbage (missing values, missing keys, non-grants prose).
# The valid '.gitignore: append-only' entry still applies.

STAGE="$SANDBOX/adopt-apply-malformed-grants"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
RC_FILE="$STAGE/rc.txt"

# --- Script did not crash on the malformed YAML ---
assert "apply produced output" "[ -f '$OUT' ]"
assert "apply did not abort -- ran to completion (RC=0)" \
    "[ \"\$(cat '$RC_FILE')\" = 0 ]"

# --- The valid entry was picked up and applied ---
assert "header reports the grants file was detected" \
    "grep -qE 'Grants file:.*\\.llm-wiki-adopt-grants\\.yml' '$OUT'"
assert "TOUCH block lists .gitignore (the only valid entry)" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qE '~ +\\.gitignore +append-only'"
assert "manifest reports .gitignore append-only as applied" \
    "grep -qF '.gitignore (append-only): applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "host .gitignore got the sentinel-paired block" \
    "grep -qF '<!-- lw:wiki-rules -->' '$HOST/.gitignore'"

# --- Garbage lines did NOT classify ---
# 'CLAUDE.md:' (no value) should be skipped, not classified as a grant.
# 'malformed line with no colon' should be skipped, ditto.
# ': value-without-key' should be skipped.
# 'trailing garbage at the bottom' should be skipped.
assert "manifest does NOT list CLAUDE.md (was malformed key with no value)" \
    "! grep -qF 'CLAUDE.md (' '$HOST/.llm-wiki-adopt-log.md'"
assert "TOUCH block does NOT list a 'malformed' or 'garbage' entry" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qiE 'malformed|garbage|value-without-key'"
assert "GRANT WARNINGS section does NOT report nonsense entries either" \
    "! awk '/^GRANT WARNINGS/,/^\$/' '$OUT' | grep -qiE 'malformed|garbage|value-without-key'"

# --- Apply completed successfully end-to-end (Phase 2A worked despite YAML mess) ---
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest reports overlay setup ran (whether applied or skipped)" \
    "grep -qE -- '- overlay setup: (applied|skipped|failed)' '$HOST/.llm-wiki-adopt-log.md'"

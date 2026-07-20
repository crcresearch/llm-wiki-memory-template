#!/usr/bin/env bash
# Assertions: adopt.sh --dry-run --agent=cursor classifies Cursor overlay
# ADD paths and agent-gated default TOUCH grants.

STAGE="$SANDBOX/adopt-shape-cursor"
HOST="$STAGE/host"
OUT="$STAGE/adopt-output.txt"

assert "patch produced an output file" "[ -f '$OUT' ]"

assert "prints dry-run banner" \
    "grep -qF 'adopt.sh --dry-run' '$OUT'"
assert "header reports agent overlay cursor" \
    "grep -qF 'Agent overlay:    cursor' '$OUT'"
assert "header reports grants source as defaults" \
    "grep -qE 'Grants file:\\s+defaults' '$OUT'"
assert "did NOT die with 'cursor is not yet supported'" \
    "! grep -qiE 'cursor.*not yet supported' '$OUT'"

# ADD includes Cursor overlay paths (not Claude).
assert "ADD block lists .cursor/rules/wiki-as-memory.mdc" \
    "awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ .cursor/rules/wiki-as-memory.mdc'"
assert "ADD block lists wiki/agents/cursor/setup.sh" \
    "awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ wiki/agents/cursor/setup.sh'"
assert "ADD block lists .cursor/skills/wiki-experiment/SKILL.md" \
    "awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ .cursor/skills/wiki-experiment/SKILL.md'"
assert "ADD block does NOT list wiki/agents/claude-code/setup.sh" \
    "! awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ wiki/agents/claude-code/setup.sh'"
assert "ADD block does NOT list .claude/commands/wiki-experiment.md" \
    "! awk '/^ADD/,/^\$/' '$OUT' | grep -qF '+ .claude/commands/wiki-experiment.md'"

# TOUCH defaults: shared + cursor merge; not Claude settings.json.
assert "TOUCH section lists 3 files (cursor defaults)" \
    "grep -qF 'TOUCH (host-owned, granted' '$OUT' && \\
     grep -qF '3 files)' '$OUT'"
assert "TOUCH section lists CLAUDE.md" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md'"
assert "TOUCH section lists .gitignore" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.gitignore'"
assert "TOUCH section lists .cursor/hooks.json" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.cursor/hooks.json'"
assert "TOUCH section does NOT list .claude/settings.json" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.claude/settings.json'"

assert "dry-run announces no writes occurred" \
    "grep -qF 'Dry-run only. No files in' '$OUT'"
assert "host did not gain .cursor/rules/wiki-as-memory.mdc" \
    "[ ! -e '$HOST/.cursor/rules/wiki-as-memory.mdc' ]"

#!/usr/bin/env bash
# Assertions: adopt --apply --agent=cursor on a virgin host.

STAGE="$SANDBOX/adopt-apply-virgin-cursor"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
# Origin slug used by lw_name_from_origin
REPO_NAME="virgin-cursor-host"

assert "apply produced an output file" "[ -f '$OUT' ]"
assert "apply did NOT emit the 'already adopted' advisory" \
    "! grep -qF 'already adopted the wiki-memory pattern' '$OUT'"
assert "apply reports Applied: N file(s) summary" \
    "grep -qE 'Applied: [0-9]+ file\\(s\\) created' '$OUT'"
assert "header reports agent overlay cursor" \
    "grep -qF 'Agent overlay:    cursor' '$OUT'"

# Cursor overlay files landed.
assert ".cursor/rules/wiki-as-memory.mdc was ADDed" \
    "[ -f '$HOST/.cursor/rules/wiki-as-memory.mdc' ]"
assert ".cursor/skills/wiki-experiment/SKILL.md was ADDed" \
    "[ -f '$HOST/.cursor/skills/wiki-experiment/SKILL.md' ]"
assert "wiki/agents/cursor/setup.sh was ADDed" \
    "[ -f '$HOST/wiki/agents/cursor/setup.sh' ]"
assert "Claude overlay was NOT ADDed" \
    "[ ! -e '$HOST/wiki/agents/claude-code/setup.sh' ]"

# {{REPO_NAME}} substituted on ADD (not left as placeholder).
assert "wiki-as-memory.mdc has no {{REPO_NAME}} placeholder" \
    "! grep -qF '{{REPO_NAME}}' '$HOST/.cursor/rules/wiki-as-memory.mdc'"
assert "wiki-as-memory.mdc contains resolved wiki path" \
    "grep -qF 'wiki/${REPO_NAME}.wiki/' '$HOST/.cursor/rules/wiki-as-memory.mdc'"
assert "wiki-experiment skill has no {{REPO_NAME}} placeholder" \
    "! grep -qF '{{REPO_NAME}}' '$HOST/.cursor/skills/wiki-experiment/SKILL.md'"

# .cursorignore stamped from template.
assert ".cursorignore was stamped" \
    "[ -f '$HOST/.cursorignore' ]"
assert "manifest records cursorignore: applied" \
    "grep -qF 'cursorignore: applied' '$HOST/.llm-wiki-adopt-log.md'"

# Merge TOUCH: sessionStart hooks via setup.sh --hook.
assert ".cursor/hooks.json was created" \
    "[ -f '$HOST/.cursor/hooks.json' ]"
assert ".cursor/hooks.json registers sessionStart" \
    "grep -qF 'sessionStart' '$HOST/.cursor/hooks.json'"
assert ".cursor/hooks/session-start.sh exists" \
    "[ -f '$HOST/.cursor/hooks/session-start.sh' ]"
assert ".cursor/hooks/ensure-wiki.sh exists" \
    "[ -f '$HOST/.cursor/hooks/ensure-wiki.sh' ]"
assert "manifest records .cursor/hooks.json merge" \
    "grep -qF '.cursor/hooks.json (merge):' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT claim .claude/settings.json merge" \
    "! grep -qF '.claude/settings.json' '$HOST/.llm-wiki-adopt-log.md'"

# Shared TOUCH still applied.
assert ".gitignore gained wiki/*.wiki/ rule" \
    "grep -qF 'wiki/*.wiki/' '$HOST/.gitignore'"
assert "overlay setup recorded as applied" \
    "grep -qF 'overlay setup: applied' '$HOST/.llm-wiki-adopt-log.md'"

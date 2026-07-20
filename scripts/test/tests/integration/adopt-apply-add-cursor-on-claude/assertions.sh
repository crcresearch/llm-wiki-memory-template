#!/usr/bin/env bash
# Assertions: --force --agent=cursor on a Claude-adopted host ADDs the
# Cursor overlay; Claude files remain; Cursor setup runs.

STAGE="$SANDBOX/adopt-apply-add-cursor-on-claude"
HOST="$STAGE/host"
OUT1="$STAGE/apply-claude.txt"
OUT2="$STAGE/apply-cursor.txt"
REPO_NAME="claude-then-cursor"

assert "claude adopt produced output" "[ -f '$OUT1' ]"
assert "cursor adopt produced output" "[ -f '$OUT2' ]"

assert "cursor apply did NOT advisory-abort (used --force)" \
    "! grep -qF 'already adopted the wiki-memory pattern' '$OUT2'"
assert "cursor apply reports Applied summary" \
    "grep -qE 'Applied: [0-9]+ file\\(s\\) created' '$OUT2'"
assert "cursor apply header says agent=cursor" \
    "grep -qF 'Agent overlay:    cursor' '$OUT2'"

# Cursor overlay ADDed.
assert "Cursor rule was ADDed" \
    "[ -f '$HOST/.cursor/rules/wiki-as-memory.mdc' ]"
assert "Cursor skill was ADDed" \
    "[ -f '$HOST/.cursor/skills/wiki-lint/SKILL.md' ]"
assert "Cursor setup.sh was ADDed" \
    "[ -f '$HOST/wiki/agents/cursor/setup.sh' ]"
assert "Cursor rule has no {{REPO_NAME}} placeholder" \
    "! grep -qF '{{REPO_NAME}}' '$HOST/.cursor/rules/wiki-as-memory.mdc'"
assert "Cursor rule resolves wiki name" \
    "grep -qF 'wiki/${REPO_NAME}.wiki/' '$HOST/.cursor/rules/wiki-as-memory.mdc'"

# Claude overlay still present (not pruned by cursor adopt).
assert "Claude setup.sh still present" \
    "[ -f '$HOST/wiki/agents/claude-code/setup.sh' ]"
assert "Claude command still present" \
    "[ -f '$HOST/.claude/commands/wiki-experiment.md' ]"

# Shared infra still present.
assert "llm-wiki.md still present" "[ -f '$HOST/llm-wiki.md' ]"
assert "discipline-gates.md still present" \
    "[ -f '$HOST/wiki/agents/discipline-gates.md' ]"

# Cursor setup ran; .cursorignore stamped.
assert "overlay setup applied for cursor run" \
    "grep -qF 'overlay setup: applied' '$HOST/.llm-wiki-adopt-log.md'"
assert ".cursorignore stamped" "[ -f '$HOST/.cursorignore' ]"
assert "latest adopt log entry records agent: cursor" \
    "tail -n 30 '$HOST/.llm-wiki-adopt-log.md' | grep -qF -- '- agent: cursor'"

# ADD section of cursor run should list Cursor paths (not re-ADD shared
# files that are already byte-equal / SKIP).
assert "cursor dry-run-style ADD in apply output lists wiki/agents/cursor/setup.sh or Applied includes it" \
    "grep -qF 'wiki/agents/cursor/setup.sh' '$OUT2' || grep -qF 'wiki/agents/cursor/setup.sh' '$HOST/.llm-wiki-adopt-log.md'"

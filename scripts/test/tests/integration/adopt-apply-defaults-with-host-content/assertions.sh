#!/usr/bin/env bash
# Assertions: with the three integration files preauthored AND no
# grants file, the default-grants path classifies them as TOUCH with
# was_absent=0, and the apply path MODIFIES them (preserving host
# content) rather than 'create from canonical'. Verifies the
# defaults path discriminates absent vs present targets correctly.

STAGE="$SANDBOX/adopt-apply-defaults-with-host-content"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "header reports grants source as 'defaults'" \
    "grep -qE 'Grants file:\\s+defaults' '$OUT'"

# TOUCH rows do NOT carry the '[absent; will create from canonical]'
# marker since the host has all three files.
assert "TOUCH row for CLAUDE.md does NOT show absent marker" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -q 'CLAUDE.md.*\\[absent'"
assert "TOUCH row for .gitignore does NOT show absent marker" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -q '\\.gitignore.*\\[absent'"
assert "TOUCH row for .claude/settings.json does NOT show absent marker" \
    "! awk '/^TOUCH/,/^\$/' '$OUT' | grep -q '\\.claude/settings.json.*\\[absent'"

# Manifest uses 'applied' (not 'created from canonical') for all three.
assert "manifest reports CLAUDE.md as applied (not created from canonical)" \
    "grep -qF 'CLAUDE.md (managed-block): applied via wiki/agents/claude-code/setup.sh' '$HOST/.llm-wiki-adopt-log.md' && \\
     ! grep -qF 'CLAUDE.md (managed-block): created from canonical' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports .gitignore as applied (not created from canonical)" \
    "grep -qF '.gitignore (append-only): applied' '$HOST/.llm-wiki-adopt-log.md' && \\
     ! grep -qF '.gitignore (append-only): created from canonical' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports settings.json as applied (not created from canonical)" \
    "grep -qF '.claude/settings.json (merge): applied via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md' && \\
     ! grep -qF '.claude/settings.json (merge): created from canonical' '$HOST/.llm-wiki-adopt-log.md'"

# Host content survives across all three.
assert "CLAUDE.md preserves host's title" \
    "grep -qFx '# Defaults With Host Content' '$HOST/CLAUDE.md'"
assert "CLAUDE.md gained the overlay's sentinel blocks" \
    "grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md' && \\
     grep -qF '<!-- lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"
assert ".gitignore preserves host's *.npz rule" \
    "grep -qFx '*.npz' '$HOST/.gitignore'"
assert ".gitignore gained the wiki/*.wiki/ rule" \
    "grep -qF 'wiki/*.wiki/' '$HOST/.gitignore'"
assert ".claude/settings.json preserves host's theme=host" \
    "grep -qF '\"theme\": \"host\"' '$HOST/.claude/settings.json'"
assert ".claude/settings.json preserves host's permissions.allow.Bash" \
    "grep -qF 'Bash' '$HOST/.claude/settings.json'"
assert ".claude/settings.json gained the SessionStart hook" \
    "grep -qF 'SessionStart' '$HOST/.claude/settings.json'"

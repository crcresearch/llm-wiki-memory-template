#!/usr/bin/env bash
# Assertions: with no .llm-wiki-adopt-grants.yml, adopt uses
# DEFAULT_GRANTS automatically. The three standard touches fire as if
# the host had hand-authored them, host's preexisting .gitignore prose
# survives, and the dry-run/manifest are explicit about the source
# being defaults so the host can audit and override.

STAGE="$SANDBOX/adopt-apply-defaults-no-grants-file"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"

# Header is honest about the source of grants.
assert "header reports grants source as 'defaults', not 'not present'" \
    "grep -qE 'Grants file:\\s+defaults' '$OUT'"
assert "header surfaces the override mechanism in plain text" \
    "grep -qF 'commit one to override' '$OUT'"
assert "header does NOT call grants 'not present' (old behaviour)" \
    "! grep -qF 'Grants file:      not present' '$OUT'"

# TOUCH section lists exactly the three default targets.
assert "TOUCH section lists 3 files (the three defaults)" \
    "grep -qF 'TOUCH (host-owned, granted' '$OUT' && \\
     grep -qF '3 files)' '$OUT'"
assert "TOUCH section lists CLAUDE.md" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF 'CLAUDE.md'"
assert "TOUCH section lists .gitignore" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.gitignore'"
assert "TOUCH section lists .claude/settings.json" \
    "awk '/^TOUCH/,/^\$/' '$OUT' | grep -qF '.claude/settings.json'"

# GRANT WARNINGS section absent (no INVALID grants in the defaults).
assert "GRANT WARNINGS section is not emitted (defaults are well-formed)" \
    "! grep -qF 'GRANT WARNINGS' '$OUT'"

# Three integration touchpoints on disk.
assert "CLAUDE.md exists with both overlay sentinel blocks" \
    "grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md' && \\
     grep -qF '<!-- lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"
assert ".gitignore gained the wiki/*.wiki/ rule" \
    "grep -qF 'wiki/*.wiki/' '$HOST/.gitignore'"
assert ".gitignore preserved host's prior '*.pyc' rule" \
    "grep -qFx '*.pyc' '$HOST/.gitignore'"
assert ".claude/settings.json was created" \
    "[ -f '$HOST/.claude/settings.json' ]"
assert ".claude/settings.json contains a SessionStart hook entry" \
    "grep -qF 'SessionStart' '$HOST/.claude/settings.json'"

# Manifest reports all three with the right status strings.
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest lists CLAUDE.md (managed-block): created from canonical and patched" \
    "grep -qF 'CLAUDE.md (managed-block): created from canonical and patched' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest lists .gitignore (append-only): applied (host had .gitignore preserving *.pyc)" \
    "grep -qF '.gitignore (append-only): applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest lists .claude/settings.json (merge): created from canonical via setup.sh --hook" \
    "grep -qF '.claude/settings.json (merge): created from canonical via wiki/agents/claude-code/setup.sh --hook' '$HOST/.llm-wiki-adopt-log.md'"

# Adopt did NOT create the .llm-wiki-adopt-grants.yml file (defaults
# are in-memory; the tool requesting permission does not mint it).
assert "adopt did NOT silently write .llm-wiki-adopt-grants.yml to the host" \
    "[ ! -f '$HOST/.llm-wiki-adopt-grants.yml' ]"

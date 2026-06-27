#!/usr/bin/env bash
# Assertions: --agent=none on a virgin host with managed-block and merge
# grants. Overlay setup must NOT run; managed-block and merge TOUCHes
# must be recorded as 'skipped' (not failed, not applied); host's
# CLAUDE.md must remain entirely unchanged (no sentinel injection).

STAGE="$SANDBOX/adopt-apply-agent-none"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "header reports Agent overlay: none" \
    "grep -qF 'Agent overlay:    none' '$OUT'"

# Overlay setup is skipped entirely (no claude-code setup.sh invocation).
assert "manifest reports overlay setup as skipped (--agent=none)" \
    "grep -qF -- '- overlay setup: skipped' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest detail mentions '--agent=none' as the reason" \
    "grep -qF -- '--agent=none, no overlay' '$HOST/.llm-wiki-adopt-log.md'"

# managed-block TOUCH records 'skipped', not 'applied' and not 'failed'.
assert "manifest reports CLAUDE.md managed-block as skipped" \
    "grep -qF 'CLAUDE.md (managed-block): skipped' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT report managed-block as applied" \
    "! grep -qF 'CLAUDE.md (managed-block): applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT report managed-block as failed" \
    "! grep -qF 'CLAUDE.md (managed-block): failed' '$HOST/.llm-wiki-adopt-log.md'"

# Same story for the merge grant.
assert "manifest reports settings.json merge as skipped" \
    "grep -qF '.claude/settings.json (merge): skipped' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT report merge as applied" \
    "! grep -qF '.claude/settings.json (merge): applied' '$HOST/.llm-wiki-adopt-log.md'"

# Host CLAUDE.md must remain entirely host-authored: no sentinels injected.
assert "host CLAUDE.md has NO lw:memory-boundary sentinel (overlay was skipped)" \
    "! grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md'"
assert "host CLAUDE.md has NO lw:wiki-maintenance sentinel" \
    "! grep -qF '<!-- lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"

# Host's prose preserved.
assert "host title preserved" \
    "grep -qFx '# Agent None Host' '$HOST/CLAUDE.md'"
assert "host conventions section preserved" \
    "grep -qFx '## Project conventions' '$HOST/CLAUDE.md'"
assert "host's settings.json was NOT modified (merge was skipped)" \
    "grep -qF '\"theme\": \"host\"' '$HOST/.claude/settings.json' && \\
     ! grep -qF 'SessionStart' '$HOST/.claude/settings.json'"

# Phase 1 ADD still ran -- init-wiki status captured as well.
assert "manifest records init-wiki status" \
    "grep -qE -- '- init-wiki: (applied|already-present)' '$HOST/.llm-wiki-adopt-log.md'"

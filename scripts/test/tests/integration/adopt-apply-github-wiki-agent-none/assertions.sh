#!/usr/bin/env bash
# Assertions: --apply --github-wiki --agent=none on a virgin host with
# fake-github origin. The github-wiki sub-step is agent-orthogonal -- the
# seed-push runs and either succeeds or fails with the 404 workaround,
# independent of which agent is consuming the wiki. The overlay setup
# (which IS agent-specific) skips with the --agent=none reason, and the
# managed-block / merge TOUCH grants that delegate to the overlay also
# skip. The wiki ignore rule still lands because it ships as the ADDed
# wiki/.gitignore, which does not depend on the overlay at all.

STAGE="$SANDBOX/adopt-apply-github-wiki-agent-none"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"
ERR="$STAGE/apply-stderr.txt"
RC_FILE="$STAGE/rc.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "adopt exited 0 (agent-none does not abort github-wiki)" \
    "[ \"\$(cat '$RC_FILE')\" = 0 ]"

# Header reports --agent=none.
assert "header reports Agent overlay: none" \
    "grep -qF 'Agent overlay:    none' '$OUT'"

# github-wiki ran (seed-push attempted on the fake URL, failed 404).
assert "manifest reports github-wiki: failed (seed-push 404)" \
    "grep -qF -- '- github-wiki: failed (seed-push 404' '$HOST/.llm-wiki-adopt-log.md'"

# init-wiki ran in local mode (no --github flag forwarded, since seed-push failed).
assert "manifest reports init-wiki: applied" \
    "grep -qE '^- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"

# Overlay setup skipped because of --agent=none.
assert "manifest reports overlay setup: skipped (--agent=none)" \
    "grep -qF -- '- overlay setup: skipped (--agent=none' '$HOST/.llm-wiki-adopt-log.md'"

# managed-block and merge TOUCH grants skipped (they delegate to overlay).
assert "TOUCH applied lists CLAUDE.md (managed-block): skipped" \
    "grep -qF 'CLAUDE.md (managed-block): skipped' '$HOST/.llm-wiki-adopt-log.md'"
assert "TOUCH applied lists .claude/settings.json (merge): skipped" \
    "grep -qF '.claude/settings.json (merge): skipped' '$HOST/.llm-wiki-adopt-log.md'"

# .gitignore is no longer a TOUCH target at all.
assert "manifest does NOT list a .gitignore TOUCH (no such grant anymore)" \
    "! grep -qF -- '- .gitignore (' '$HOST/.llm-wiki-adopt-log.md'"

# Stderr surfaces the workaround block (github-wiki failure path).
assert "stderr contains the 'Wiki bootstrap via direct push failed' header" \
    "grep -qF 'Wiki bootstrap via direct push failed' '$ERR'"

# Host's preexisting *.pyc rule survives, and nothing was appended.
assert "host .gitignore untouched (still only the host's own rule)" \
    "[ \"\$(cat '$HOST/.gitignore')\" = '*.pyc' ]"
# The wiki ignore rule landed as the ADDed wiki/.gitignore instead.
assert "wiki/.gitignore was ADDed with the *.wiki/ rule" \
    "grep -qFx '*.wiki/' '$HOST/wiki/.gitignore'"

# Overlay-managed CLAUDE.md NOT created (init-wiki seeds it from template,
# but no managed-block sentinels injected since overlay skipped).
assert "host CLAUDE.md has NO lw:memory-boundary sentinel (overlay was skipped)" \
    "! grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md' 2>/dev/null || true"

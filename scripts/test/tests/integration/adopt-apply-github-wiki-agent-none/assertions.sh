#!/usr/bin/env bash
# Assertions: --apply --github-wiki --agent=none on a virgin host with
# fake-github origin. The github-wiki sub-step is agent-orthogonal -- the
# seed-push runs and either succeeds or fails with the 404 workaround,
# independent of which agent is consuming the wiki. The overlay setup
# (which IS agent-specific) skips with the --agent=none reason, and the
# managed-block / merge TOUCH grants that delegate to the overlay also
# skip. The append-only TOUCH grant on .gitignore still runs because it
# does not depend on the overlay at all.

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

# append-only TOUCH on .gitignore still runs (no overlay dependency).
assert "TOUCH applied lists .gitignore (append-only): created from canonical or applied" \
    "grep -qE -- '- .gitignore \\(append-only\\): (created from canonical|applied)' '$HOST/.llm-wiki-adopt-log.md'"

# Stderr surfaces the workaround block (github-wiki failure path).
assert "stderr contains the 'Wiki bootstrap via direct push failed' header" \
    "grep -qF 'Wiki bootstrap via direct push failed' '$ERR'"

# Host's preexisting *.pyc rule survives.
assert "host .gitignore preserves preexisting *.pyc rule" \
    "grep -qFx '*.pyc' '$HOST/.gitignore'"
# Sentinel block from append-only TOUCH was added.
assert "host .gitignore gained the wiki/*.wiki/ rule" \
    "grep -qF 'wiki/*.wiki/' '$HOST/.gitignore'"

# Overlay-managed CLAUDE.md NOT created (init-wiki seeds it from template,
# but no managed-block sentinels injected since overlay skipped).
assert "host CLAUDE.md has NO lw:memory-boundary sentinel (overlay was skipped)" \
    "! grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md' 2>/dev/null || true"

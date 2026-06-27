#!/usr/bin/env bash
# Assertions: overlay setup falls back to EOF append when CLAUDE.md has
# no '### Knowledge Graph' anchor. Host prose still preserved, sentinels
# still present and unique. The fallback is the overlay setup's design,
# not a degradation -- adopt should report success normally.

STAGE="$SANDBOX/adopt-apply-virgin-no-anchor"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

assert "apply produced output" "[ -f '$OUT' ]"
assert "apply did not abort with advisory (host was virgin)" \
    "! grep -qF 'already adopted the wiki-memory pattern' '$OUT'"

# Host content preserved (no anchor was changed, host prose intact).
assert "host's title preserved" \
    "grep -qFx '# No Anchor Host' '$HOST/CLAUDE.md'"
assert "host's '## Conventions' heading preserved" \
    "grep -qFx '## Conventions' '$HOST/CLAUDE.md'"
assert "host's LAST_HOST_LINE marker preserved" \
    "grep -qFx 'LAST_HOST_LINE' '$HOST/CLAUDE.md'"

# Sentinels injected (overlay setup ran).
assert "lw:memory-boundary opening sentinel injected" \
    "grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md'"
assert "lw:wiki-maintenance opening sentinel injected" \
    "grep -qF '<!-- lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"

# Each appears exactly once.
mb=$(grep -cF '<!-- lw:memory-boundary -->' "$HOST/CLAUDE.md" || true)
wm=$(grep -cF '<!-- lw:wiki-maintenance -->' "$HOST/CLAUDE.md" || true)
assert "lw:memory-boundary opening sentinel appears exactly once" \
    "[ '$mb' -eq 1 ]"
assert "lw:wiki-maintenance opening sentinel appears exactly once" \
    "[ '$wm' -eq 1 ]"

# Fallback path: sentinels land AFTER the host's LAST_HOST_LINE marker
# (no '### Knowledge Graph' anchor, so lw_inject_block appends at EOF).
last_line=$(grep -nFx 'LAST_HOST_LINE' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
mb_line=$(grep -n '<!-- lw:memory-boundary -->' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
wm_line=$(grep -n '<!-- lw:wiki-maintenance -->' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
assert "fallback: memory-boundary lands AFTER host's last line (no anchor)" \
    "[ '$last_line' -lt '$mb_line' ]"
assert "fallback: wiki-maintenance lands AFTER host's last line (no anchor)" \
    "[ '$last_line' -lt '$wm_line' ]"

# Manifest reports overlay setup as applied (the fallback is success).
assert "manifest reports overlay setup as applied" \
    "grep -qF -- '- overlay setup: applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest reports CLAUDE.md managed-block as applied via overlay setup.sh" \
    "grep -qF 'CLAUDE.md (managed-block): applied via wiki/agents/claude-code/setup.sh' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT report managed-block as failed" \
    "! grep -qF 'CLAUDE.md (managed-block): failed' '$HOST/.llm-wiki-adopt-log.md'"

#!/usr/bin/env bash
# Assertions: adopt --apply on a virgin host that already has its own
# CLAUDE.md. Verifies the additive-overlay contract: the overlay setup
# injects sentinel-paired blocks INTO the host's CLAUDE.md without
# overwriting or losing the host's existing prose.

STAGE="$SANDBOX/adopt-apply-virgin-with-claude"
HOST="$STAGE/host"
OUT="$STAGE/apply-output.txt"

# --- Apply succeeded (no advisory abort, no errors) ---
assert "apply produced an output file" "[ -f '$OUT' ]"
assert "apply did NOT emit the 'already adopted' advisory (host was virgin)" \
    "! grep -qF 'already adopted the wiki-memory pattern' '$OUT'"
assert "apply reports the Applied: N file(s) summary" \
    "grep -qE 'Applied: [0-9]+ file\\(s\\) created' '$OUT'"

# --- Host CLAUDE.md prose ABOVE and BELOW the injection points preserved ---
assert "host's title line preserved" \
    "grep -qF '# Virgin Claude Host' '$HOST/CLAUDE.md'"
assert "host's pre-adoption preamble preserved" \
    "grep -qF 'authored by the project owner before adoption' '$HOST/CLAUDE.md'"
assert "host's '## Project conventions' section preserved" \
    "grep -qF '## Project conventions' '$HOST/CLAUDE.md'"
assert "host's closing prose preserved" \
    "grep -qF 'must survive adoption unchanged' '$HOST/CLAUDE.md'"

# --- Overlay setup injected the sentinel-paired blocks ---
assert "lw:memory-boundary opening sentinel injected" \
    "grep -qF '<!-- lw:memory-boundary -->' '$HOST/CLAUDE.md'"
assert "lw:memory-boundary closing sentinel injected" \
    "grep -qF '<!-- /lw:memory-boundary -->' '$HOST/CLAUDE.md'"
assert "lw:wiki-maintenance opening sentinel injected" \
    "grep -qF '<!-- lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"
assert "lw:wiki-maintenance closing sentinel injected" \
    "grep -qF '<!-- /lw:wiki-maintenance -->' '$HOST/CLAUDE.md'"

# --- Each managed block appears exactly once (no double-injection) ---
mb_open=$(grep -cF '<!-- lw:memory-boundary -->' "$HOST/CLAUDE.md" || true)
assert "lw:memory-boundary opening sentinel appears exactly once" \
    "[ '$mb_open' -eq 1 ]"
wm_open=$(grep -cF '<!-- lw:wiki-maintenance -->' "$HOST/CLAUDE.md" || true)
assert "lw:wiki-maintenance opening sentinel appears exactly once" \
    "[ '$wm_open' -eq 1 ]"

# --- Manifest captures the managed-block apply via overlay setup.sh ---
assert "manifest exists" "[ -f '$HOST/.llm-wiki-adopt-log.md' ]"
assert "manifest records CLAUDE.md managed-block applied via setup.sh" \
    "grep -qF 'CLAUDE.md (managed-block): applied via wiki/agents/claude-code/setup.sh' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest does NOT report managed-block as failed" \
    "! grep -qF 'CLAUDE.md (managed-block): failed' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records init-wiki as applied (first run on virgin host)" \
    "grep -qF -- '- init-wiki: applied' '$HOST/.llm-wiki-adopt-log.md'"
assert "manifest records overlay setup as applied" \
    "grep -qF -- '- overlay setup: applied' '$HOST/.llm-wiki-adopt-log.md'"

# --- Wiki sub-repo was created by init-wiki ---
assert "wiki sub-repo created at wiki/virgin-claude-host.wiki/" \
    "[ -d '$HOST/wiki/virgin-claude-host.wiki/.git' ]"

# --- After --apply, composite detector should now see this host as adopted ---
# Re-running --apply (no --force) should fire the advisory. Need to commit
# everything first to keep the working tree clean (the wiki sub-repo embeds
# its own .git inside the host; --add ignores its contents but the entry
# itself counts).
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A 2>/dev/null
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "after apply" \
    >/dev/null 2>&1 || true
ADOPT_ABS="$(cd "$HERE/.." && pwd)/adopt.sh"
RERUN_OUT="$STAGE/rerun.txt"
RERUN_RC=0
bash "$ADOPT_ABS" --target="$HOST" --apply > "$RERUN_OUT" 2>&1 || RERUN_RC=$?
assert "re-running --apply on the now-adopted host exits non-zero" \
    "[ '$RERUN_RC' -ne 0 ]"
assert "re-running --apply on the now-adopted host fires the advisory" \
    "grep -qF 'already adopted the wiki-memory pattern' '$RERUN_OUT'"

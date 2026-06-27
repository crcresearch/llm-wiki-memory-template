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

# --- Sentinel positioning: both blocks land BEFORE the ### Knowledge Graph anchor ---
mb_line=$(grep -n '<!-- lw:memory-boundary -->' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
wm_open_line=$(grep -n '<!-- lw:wiki-maintenance -->' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
kg_line=$(grep -n '^### Knowledge Graph' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
assert "lw:memory-boundary sits BEFORE the ### Knowledge Graph anchor" \
    "[ '$mb_line' -lt '$kg_line' ]"
assert "lw:wiki-maintenance sits BEFORE the ### Knowledge Graph anchor" \
    "[ '$wm_open_line' -lt '$kg_line' ]"
# The anchor used is the HOST's pre-adoption anchor, not one init-wiki
# happens to add as a fallback. Locking onto the host's distinctive
# comment ensures we are checking the right anchor.
assert "host's pre-adoption KG anchor and its comment are still adjacent" \
    "grep -A2 '^### Knowledge Graph' '$HOST/CLAUDE.md' | grep -qF '(Anchor where the overlay'"
# Memory-boundary precedes wiki-maintenance (overlay's own ordering contract).
assert "memory-boundary precedes wiki-maintenance" \
    "[ '$mb_line' -lt '$wm_open_line' ]"
# Both sentinels are INSIDE the host's '## Wiki' section (after the heading).
host_wiki_heading=$(grep -n '^## Wiki$' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
assert "sentinels are inside the host's '## Wiki' section (after the heading)" \
    "[ '$host_wiki_heading' -lt '$mb_line' ]"

# --- Host content ordering (full-line exact-match grep -qFx) ---
# The substring assertions above can be fooled by adjacent edits; grep -Fx
# locks each marker line to byte-equal-line presence, and the line-number
# checks below lock their ordering.
assert "host title is byte-exact preserved" \
    "grep -qFx '# Virgin Claude Host' '$HOST/CLAUDE.md'"
assert "host preamble line is byte-exact preserved" \
    "grep -qFx 'This CLAUDE.md was authored by the project owner before adoption.' '$HOST/CLAUDE.md'"
assert "host's '## Wiki' heading is byte-exact preserved" \
    "grep -qFx '## Wiki' '$HOST/CLAUDE.md'"
assert "host's '## Project conventions' heading is byte-exact preserved" \
    "grep -qFx '## Project conventions' '$HOST/CLAUDE.md'"
assert "host's closing prose line is byte-exact preserved" \
    "grep -qFx 'These conventions are host-authored and must survive adoption unchanged.' '$HOST/CLAUDE.md'"

title_line=$(grep -nFx '# Virgin Claude Host' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
preamble_line=$(grep -nFx 'This CLAUDE.md was authored by the project owner before adoption.' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
conventions_line=$(grep -nFx '## Project conventions' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
closing_line=$(grep -nFx 'These conventions are host-authored and must survive adoption unchanged.' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
assert "host content order: title -> preamble" \
    "[ '$title_line' -lt '$preamble_line' ]"
assert "host content order: preamble -> '## Wiki' heading" \
    "[ '$preamble_line' -lt '$host_wiki_heading' ]"
assert "host content order: '## Wiki' -> '## Project conventions'" \
    "[ '$host_wiki_heading' -lt '$conventions_line' ]"
assert "host content order: '## Project conventions' -> closing line" \
    "[ '$conventions_line' -lt '$closing_line' ]"

# --- init-wiki also writes to CLAUDE.md: documentation referencing SCHEMA file ---
# init-wiki's 'Updated CLAUDE.md: + Knowledge Graph subsection' step injects
# wiki-related documentation. Verify the injection happened by looking for
# the SCHEMA reference it uses (the wiki sub-repo name is substituted in).
assert "init-wiki added documentation referencing the SCHEMA file" \
    "grep -qF 'SCHEMA_virgin-claude-host.md' '$HOST/CLAUDE.md'"
assert "init-wiki added the wiki sub-repo path reference" \
    "grep -qF 'wiki/virgin-claude-host.wiki' '$HOST/CLAUDE.md'"
# init-wiki's content lands AFTER all host content (appended at end).
# The phrase 'Read `wiki/.../SCHEMA_*.md` before making wiki changes' is
# unique to init-wiki's CLAUDE.md update step (the wiki-maintenance
# sentinel block uses different phrasing).
init_wiki_line=$(grep -nF 'before making wiki changes' "$HOST/CLAUDE.md" | head -1 | cut -d: -f1)
assert "init-wiki added the 'before making wiki changes' guidance line" \
    "[ -n '$init_wiki_line' ]"
assert "init-wiki documentation lands AFTER host's closing line" \
    "[ '$closing_line' -lt '$init_wiki_line' ]"

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

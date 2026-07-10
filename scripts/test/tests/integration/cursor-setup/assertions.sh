#!/usr/bin/env bash
# Assertions: run the real cursor/setup.sh against staged fixtures and verify
# the shared-library wiring:
#   - identity comes from the on-disk wiki, not the clone directory name;
#   - the CLAUDE.md snippet is genuinely injected before the Knowledge Graph
#     anchor (the BSD-safe lw_insert_before path, which the old `awk -v`
#     no-opped on);
#   - a re-run is a byte-for-byte no-op (true idempotency);
#   - --legacy renders .cursorrules with the wiki name and skips on re-run;
#   - a missing wiki fails loud, for the wiki reason.
#
# Anti-vacuity note: the shipped snippet currently leaks its HTML-comment
# header into CLAUDE.md (a pre-existing bug shared with claude-code), and
# that leaked text quotes the marker strings. So a substring grep for a
# marker (grep -F '### Wiki maintenance behavior') matches the leaked
# comment even when nothing was injected -- it cannot prove injection
# happened. These assertions therefore use either the rendered wiki path
# (which only appears in the real body) or anchored, whole-line matches
# (^### ...$, which the indented/quoted comment line does not satisfy).
#
# setup.sh locates the library from its own path, but takes the project
# root from the current directory, so each run cds into a fixture.

STAGE="$SANDBOX/cursor-setup"

# patch.sh declines to stage (no $STAGE dir) when the checkout is not the
# template — derived projects lack .cursorrules.template and .cursor/rules.
if [ ! -d "$STAGE" ]; then
    skip "cursor-setup assertions" "not a template checkout (derived project; cursor fixtures unavailable)"
    return 0 2>/dev/null || true
fi

# assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
REPO_ROOT_CU="$(cd "$HERE/../.." && pwd)"
SETUP="$REPO_ROOT_CU/wiki/agents/cursor/setup.sh"

assert "setup.sh exists"            "[ -f '$SETUP' ]"
assert "setup.sh passes bash -n"    "bash -n '$SETUP'"

# --- Identity + injection: rendered wiki path proves the real body landed ---
# Dir basename is 'checkout'; wiki is 'glyph'. The rendered path
# 'wiki/glyph.wiki/' appears ONLY in the injected subsection body (never in
# the leaked comment), so finding it proves the injection actually ran AND
# used the wiki-derived name rather than the clone-directory basename.
( cd "$STAGE/checkout" && bash "$SETUP" ) >/dev/null 2>&1
assert "injection+identity: rendered wiki path 'wiki/glyph.wiki/' present" \
    "grep -qF 'wiki/glyph.wiki/' '$STAGE/checkout/CLAUDE.md'"
assert "identity: clone dir name 'wiki/checkout.wiki/' NOT used" \
    "! grep -qF 'wiki/checkout.wiki/' '$STAGE/checkout/CLAUDE.md'"
assert "injection: baseline CLAUDE.md content preserved" \
    "grep -qF 'Baseline content that must be preserved' '$STAGE/checkout/CLAUDE.md'"

# --- Injection: real (whole-line) headers present exactly once ---
# Anchored ^...$ excludes the leaked comment line, so a count of 1 proves
# the genuine subsection header was injected (not just the comment).
assert_eq "injection: one real '### Wiki maintenance behavior' header" "1" \
    "$(grep -cE '^### Wiki maintenance behavior$' "$STAGE/checkout/CLAUDE.md")"
assert_eq "injection: one real '### Memory boundary' header" "1" \
    "$(grep -cE '^### Memory boundary$' "$STAGE/checkout/CLAUDE.md")"

# --- Injection: the real subsection precedes the Knowledge Graph anchor ---
# Anchored patterns so the leaked comment (which mentions the marker as a
# quoted substring) cannot stand in for the real header.
assert "injection: real subsection precedes '### Knowledge Graph'" \
    "awk '/^### Wiki maintenance behavior\$/{s=NR} /^### Knowledge Graph\$/{m=NR} END{exit !(s>0 && m>0 && s<m)}' '$STAGE/checkout/CLAUDE.md'"

# --- Idempotency: a second run is a byte-for-byte no-op ---
# Stronger than counting markers: snapshot, re-run, assert the file is
# unchanged. Immune to the comment-leak quirk entirely.
cp "$STAGE/checkout/CLAUDE.md" "$STAGE/checkout/CLAUDE.md.snap1"
( cd "$STAGE/checkout" && bash "$SETUP" ) >/dev/null 2>&1
assert "idempotent: re-run leaves CLAUDE.md byte-identical" \
    "diff -q '$STAGE/checkout/CLAUDE.md.snap1' '$STAGE/checkout/CLAUDE.md'"

# --- --legacy: .cursorrules rendered with the wiki name, idempotent ---
( cd "$STAGE/checkout" && bash "$SETUP" --legacy ) >/dev/null 2>&1
assert "legacy: .cursorrules created" "[ -f '$STAGE/checkout/.cursorrules' ]"
assert "legacy: .cursorrules rendered with the wiki name (wiki/glyph.wiki/)" \
    "grep -qF 'wiki/glyph.wiki/' '$STAGE/checkout/.cursorrules'"
assert "legacy: no unsubstituted {{REPO_NAME}} placeholder remains" \
    "! grep -qF '{{REPO_NAME}}' '$STAGE/checkout/.cursorrules'"
OUT_LEGACY="$( cd "$STAGE/checkout" && bash "$SETUP" --legacy 2>&1 )"
LEGACY_SKIP=0; case "$OUT_LEGACY" in *".cursorrules: already present"*) LEGACY_SKIP=1 ;; esac
assert "legacy: re-run skips the existing .cursorrules" "[ $LEGACY_SKIP -eq 1 ]"

# --- Fail-loud: no wiki present -> non-zero exit, for the wiki reason ---
ERR_NOWIKI="$( cd "$STAGE/nowiki" && bash "$SETUP" 2>&1 )"
RC=$?
assert "no wiki: setup.sh exits non-zero" "[ $RC -ne 0 ]"
NOWIKI_MSG=0; case "$ERR_NOWIKI" in *no\ wiki*|*"wiki not found"*) NOWIKI_MSG=1 ;; esac
assert "no wiki: failure names the missing wiki (not an unrelated error)" "[ $NOWIKI_MSG -eq 1 ]"

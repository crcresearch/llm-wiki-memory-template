#!/usr/bin/env bash
# Assertions: run the real cursor/setup.sh against staged fixtures and verify:
#   - the host's CLAUDE.md is never touched (byte-identical across runs; the
#     old overlay injected subsections into it, and that writer is retired);
#   - the rules verification reports the full .cursor/rules/*.mdc set;
#   - identity comes from the on-disk wiki, not the clone directory name
#     (proved via the --legacy .cursorrules render, the one remaining
#     substitution path);
#   - --legacy renders .cursorrules with the wiki name and skips on re-run;
#   - a missing wiki fails loud, for the wiki reason.
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

# --- CLAUDE.md is host-owned: setup.sh must leave it byte-identical ---
# Snapshot BEFORE the first run, so an injection on run one (the retired
# behavior) fails the diff, not just a non-idempotent second run.
cp "$STAGE/checkout/CLAUDE.md" "$STAGE/checkout/CLAUDE.md.before"
OUT_BASE="$( cd "$STAGE/checkout" && bash "$SETUP" 2>&1 )"
RC_BASE=$?
assert "base run exits zero" "[ $RC_BASE -eq 0 ]"
assert "base run leaves CLAUDE.md byte-identical" \
    "diff -q '$STAGE/checkout/CLAUDE.md.before' '$STAGE/checkout/CLAUDE.md'"

# --- Rules verification: the full .mdc set is reported present ---
RULES_OK=0; case "$OUT_BASE" in *"all five present"*) RULES_OK=1 ;; esac
assert "base run reports all five .cursor/rules present" "[ $RULES_OK -eq 1 ]"
assert "memory-boundary.mdc is part of the staged rules set" \
    "[ -f '$STAGE/checkout/.cursor/rules/memory-boundary.mdc' ]"

# --- Second run: still no CLAUDE.md drift ---
( cd "$STAGE/checkout" && bash "$SETUP" ) >/dev/null 2>&1
assert "re-run leaves CLAUDE.md byte-identical" \
    "diff -q '$STAGE/checkout/CLAUDE.md.before' '$STAGE/checkout/CLAUDE.md'"

# --- --legacy: .cursorrules rendered with the wiki name, idempotent ---
# Dir basename is 'checkout'; wiki is 'glyph'. The rendered path
# 'wiki/glyph.wiki/' proves setup.sh used the wiki-derived name rather
# than the clone-directory basename.
( cd "$STAGE/checkout" && bash "$SETUP" --legacy ) >/dev/null 2>&1
assert "legacy: .cursorrules created" "[ -f '$STAGE/checkout/.cursorrules' ]"
assert "legacy: .cursorrules rendered with the wiki name (wiki/glyph.wiki/)" \
    "grep -qF 'wiki/glyph.wiki/' '$STAGE/checkout/.cursorrules'"
assert "legacy: clone dir name 'wiki/checkout.wiki/' NOT used" \
    "! grep -qF 'wiki/checkout.wiki/' '$STAGE/checkout/.cursorrules'"
assert "legacy: no unsubstituted {{REPO_NAME}} placeholder remains" \
    "! grep -qF '{{REPO_NAME}}' '$STAGE/checkout/.cursorrules'"
OUT_LEGACY="$( cd "$STAGE/checkout" && bash "$SETUP" --legacy 2>&1 )"
LEGACY_SKIP=0; case "$OUT_LEGACY" in *".cursorrules: already present"*) LEGACY_SKIP=1 ;; esac
assert "legacy: re-run skips the existing .cursorrules" "[ $LEGACY_SKIP -eq 1 ]"
assert "legacy runs leave CLAUDE.md byte-identical" \
    "diff -q '$STAGE/checkout/CLAUDE.md.before' '$STAGE/checkout/CLAUDE.md'"

# --- Fail-loud: no wiki present -> non-zero exit, for the wiki reason ---
ERR_NOWIKI="$( cd "$STAGE/nowiki" && bash "$SETUP" 2>&1 )"
RC=$?
assert "no wiki: setup.sh exits non-zero" "[ $RC -ne 0 ]"
NOWIKI_MSG=0; case "$ERR_NOWIKI" in *no\ wiki*|*"wiki not found"*) NOWIKI_MSG=1 ;; esac
assert "no wiki: failure names the missing wiki (not an unrelated error)" "[ $NOWIKI_MSG -eq 1 ]"

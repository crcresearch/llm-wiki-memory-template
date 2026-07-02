#!/usr/bin/env bash
# Assertions: instantiate.sh names the project from origin (widget), not the
# clone-dir basename (clonedir). Exercised end-to-end through instantiate ->
# init-wiki, so it also proves the --repo-name handshake (chunk 02/03) wires
# the once-resolved name all the way to the wiki directory and file prefixes.

T="$SANDBOX/instantiate-naming/clonedir"

if [ ! -d "$T" ]; then
    skip "instantiate-naming assertions" "template not cloned (offline + no MVP_TEMPLATE_LOCAL)"
    return 0 2>/dev/null || true
fi

# Exit status first: the assertions below are presence-conditional and can
# pass against a half-bootstrapped tree (mid-run deaths were WARN-swallowed).
assert "instantiate.sh exited 0" \
    "[ \"\$(cat '$T.instantiate-rc' 2>/dev/null)\" = '0' ]"

assert "instantiate.sh produced CLAUDE.md" "[ -f '$T/CLAUDE.md' ]"

# --- F1: namespace from origin (widget), not basename (clonedir) ---
assert "F1: wiki dir uses the origin name (widget.wiki)" \
    "[ -d '$T/wiki/widget.wiki' ]"
assert "F1: wiki sub-repo created (init-wiki ran with the handed-down name)" \
    "[ -d '$T/wiki/widget.wiki/.git' ]"
assert "F1: clone-dir basename NOT used (no clonedir.wiki)" \
    "[ ! -d '$T/wiki/clonedir.wiki' ]"
assert "F1: files namespaced with the origin name (SCHEMA_widget.md)" \
    "[ -f '$T/wiki/widget.wiki/SCHEMA_widget.md' ]"
assert "F1: Home_widget.md exists" \
    "[ -f '$T/wiki/widget.wiki/Home_widget.md' ]"

# --- F1: the rendered CLAUDE.md points at the origin-named wiki path ---
assert_contains "F1: CLAUDE.md references wiki/widget.wiki/" \
    "$T/CLAUDE.md" "wiki/widget\.wiki/"
assert "F1: CLAUDE.md has no {{REPO_NAME}} leak" \
    "! grep -q '{{REPO_NAME}}' '$T/CLAUDE.md'"

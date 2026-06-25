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

# --- Template sync log seeded by instantiate.sh ---
# Before this change only update-from-template.sh wrote .llm-wiki-template-log.md,
# so a fresh instantiation left no authoritative on-disk marker that this repo
# came from the template. Now instantiate.sh seeds the file with an initial
# entry so downstream tooling (e.g. adopt.sh's "already adopted" detection)
# can rely on the marker from day one. Entry format mirrors what
# update-from-template.sh appends, so the log stays one consistent history.
assert ".llm-wiki-template-log.md was seeded on instantiation" \
    "[ -f '$T/.llm-wiki-template-log.md' ]"
assert "seed log has the top-level heading" \
    "grep -qF '# llm-wiki template sync log' '$T/.llm-wiki-template-log.md'"
assert "seed log entry names this as the initial instantiation" \
    "grep -qF 'instantiated from llm-wiki-memory-template' '$T/.llm-wiki-template-log.md'"
# The heading carries the inline config summary — agent + features — in the
# same shape as update-from-template.sh's '@SHA - N file(s) updated' pattern.
assert "seed log heading inlines agent=none summary" \
    "grep -qE '^## \\[.*\\] instantiated from llm-wiki-memory-template - agent=none' '$T/.llm-wiki-template-log.md'"
assert "seed log heading inlines features=none summary" \
    "grep -qE '^## \\[.*\\] instantiated.*features=none' '$T/.llm-wiki-template-log.md'"
# Bullets are reserved for identity fields (project, repo).
assert "seed log records project name as a bullet (Widget Project)" \
    "grep -qF -- '- project: Widget Project' '$T/.llm-wiki-template-log.md'"
assert "seed log records resolved repo slug as a bullet (widget)" \
    "grep -qF -- '- repo: widget' '$T/.llm-wiki-template-log.md'"

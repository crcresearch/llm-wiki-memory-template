#!/usr/bin/env bash
# Smoke test assertions: template bootstrap.
# Verifies the template's own scripts pass syntax checks and produce the
# expected file structure after instantiate.sh runs.

T="$SANDBOX/template"

# If clone failed (no network, no MVP_TEMPLATE_LOCAL), skip everything.
if [ ! -d "$T" ]; then
    skip "template-bootstrap assertions" "template not cloned (offline + no MVP_TEMPLATE_LOCAL)"
    return 0 2>/dev/null || true
fi

# --- Syntax checks on the template's shipping scripts ---
# These are the bash -n checks template issue #5 explicitly calls for.
for script in \
    "$T/wiki/init-wiki.sh" \
    "$T/scripts/instantiate.sh" \
    "$T/scripts/update-from-template.sh" \
    "$T/scripts/check-template-version.sh"
do
    if [ -f "$script" ]; then
        assert "bash -n $(basename "$script") (syntax)" "bash -n '$script'"
    fi
done

# Agent-overlay setup scripts (if present)
for setup in "$T/wiki/agents"/*/setup.sh; do
    if [ -f "$setup" ]; then
        rel=$(echo "$setup" | sed "s|^$T/||")
        assert "bash -n $rel (syntax)" "bash -n '$setup'"
    fi
done

# --- instantiate.sh produced the expected baseline ---
# After instantiate "Smoke Test Project" --agent=none, the template should
# have a real CLAUDE.md (substituted from CLAUDE.md.template).
if [ -f "$T/CLAUDE.md" ]; then
    assert "instantiate.sh produced CLAUDE.md" "[ -f '$T/CLAUDE.md' ]"
    assert_contains "CLAUDE.md has project name substituted (no {{PROJECT_NAME}} leak)" \
        "$T/CLAUDE.md" "Smoke Test Project"
    assert "instantiate.sh did NOT leave {{PROJECT_NAME}} placeholder" \
        "! grep -q '{{PROJECT_NAME}}' '$T/CLAUDE.md'"

    # PR #26: Memory boundary subsection is in CLAUDE.md.template, so a
    # fresh instantiation should carry it through verbatim.
    assert_contains "CLAUDE.md has '### Memory boundary' subsection" \
        "$T/CLAUDE.md" "### Memory boundary"
    assert_contains "CLAUDE.md memory boundary names Claude-memory" \
        "$T/CLAUDE.md" "Claude-memory holds"
    assert_contains "CLAUDE.md memory boundary names the wiki" \
        "$T/CLAUDE.md" "Wiki holds"
fi

# --- The parallel snippet (claude-md-snippet.md) carries the same
#     subsections. Catches parallel-file-drift on the boundary stanza:
#     if the boundary text drifts between CLAUDE.md.template and the
#     snippet, only one of these assertions fires.
SNIPPET="$T/wiki/agents/claude-code/templates/claude-md-snippet.md"
if [ -f "$SNIPPET" ]; then
    assert_contains "claude-md-snippet has '### Memory boundary' subsection" \
        "$SNIPPET" "### Memory boundary"
    assert_contains "claude-md-snippet memory boundary names Claude-memory" \
        "$SNIPPET" "Claude-memory holds"
    assert_contains "claude-md-snippet memory boundary names the wiki" \
        "$SNIPPET" "Wiki holds"
fi

# --- init-wiki.sh produced the expected wiki structure ---
# init-wiki.sh is called by instantiate.sh and creates the wiki sub-repo
# with namespaced nav files.
REPO_NAME=$(basename "$T")
WIKI_SUB="$T/wiki/${REPO_NAME}.wiki"

assert "wiki sub-repo created at wiki/${REPO_NAME}.wiki/" \
    "[ -d '$WIKI_SUB/.git' ]"
# Namespaced nav files per init-wiki.sh's documented behavior
assert "Home_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/Home_${REPO_NAME}.md' ]"
assert "index_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/index_${REPO_NAME}.md' ]"
assert "log_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/log_${REPO_NAME}.md' ]"
assert "SCHEMA_${REPO_NAME}.md exists" \
    "[ -f '$WIKI_SUB/SCHEMA_${REPO_NAME}.md' ]"
# Bridge file for GitHub wiki compatibility
assert "Home.md bridge exists at wiki root" \
    "[ -f '$WIKI_SUB/Home.md' ]"

# --- init-wiki.sh is idempotent: running it again should not error ---
# Per its docstring: "It is idempotent: safe to re-run on existing wikis
# (auto-detects create vs. update mode)."
if [ -f "$T/wiki/init-wiki.sh" ] && [ -d "$WIKI_SUB" ]; then
    RERUN_RC=$(cd "$T" && bash wiki/init-wiki.sh --name "Smoke Test Project" >/dev/null 2>&1; echo $?)
    assert_eq "init-wiki.sh is idempotent (re-runs cleanly on existing wiki)" "0" "$RERUN_RC"
fi

# --- Edge-Types.md.template was stamped into the wiki ---
# init-wiki.sh's *.md.template loop should produce wiki/<repo>.wiki/Edge-Types.md
# with placeholders substituted and the 16 forward-predicate anchored sections
# present so Variant 1 inline annotations resolve.
assert "Edge-Types.md present in the wiki" \
    "[ -f '$WIKI_SUB/Edge-Types.md' ]"

assert "Edge-Types.md has no placeholder leaks" \
    "! grep -qE '\{\{REPO_NAME\}\}|\{\{PROJECT_NAME\}\}' '$WIKI_SUB/Edge-Types.md'"

assert "Edge-Types.md up: resolves to SCHEMA_${REPO_NAME}" \
    "grep -qF 'up: \"[[SCHEMA_${REPO_NAME}]]\"' '$WIKI_SUB/Edge-Types.md'"

# All 16 anchored predicate sections (so Edge-Types#<pred> anchors resolve)
EDGE_PREDS="up source extends supports criticizes concept partOf dependsOn defines resolvedBy incorporatedInto outOfScopeFor precedes feedsInto related mentions"
ALL_PRESENT=1
for pred in $EDGE_PREDS; do
    if ! grep -qE "^## ${pred}$" "$WIKI_SUB/Edge-Types.md"; then
        ALL_PRESENT=0
        break
    fi
done
assert_eq "Edge-Types.md has all 16 forward-predicate anchored sections" "1" "$ALL_PRESENT"

# Generated SCHEMA contains the Variant 1 subsection that documents the form
assert "SCHEMA contains 'Inline body annotations (Variant 1)' subsection" \
    "grep -qF '## Inline body annotations (Variant 1)' '$WIKI_SUB/SCHEMA_${REPO_NAME}.md'"

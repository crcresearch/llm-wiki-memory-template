#!/usr/bin/env bash
# Derivative-init + template-clone helpers for the MVP test harness.
#
# init_derivative creates a stand-in for a template-bootstrapped derivative,
# decoupled from the actual init-wiki.sh logic. Used by e2e tests for fast
# iteration on MVP-specific behavior.
#
# clone_template clones (or copies from local) the real template repo. Used
# by smoke tests that exercise the template's actual bootstrap, including
# init-wiki.sh in create and update modes.
#
# Two env vars control template resolution, in order of precedence:
#   MVP_TEMPLATE_LOCAL=/path/to/clone  use a local clone (offline, fast)
#   MVP_TEMPLATE_REPO=<url>            clone from this URL (default: the
#                                       chrissweet fork of the template)

DEFAULT_TEMPLATE_REPO="https://github.com/chrissweet/llm-wiki-memory-template.git"

# Initialize a minimal derivative project:
# - git init with a known user
# - .claude/ directory ready for hooks and config
# - a wiki/<project>.wiki/ sub-repo (also git-initialized)
init_derivative() {
    local dir="$1"
    local project="${2:-test-project}"

    mkdir -p "$dir"
    cd "$dir"

    git init --quiet --initial-branch=main
    git config user.email "test-user@example.test"
    git config user.name "Test User"

    mkdir -p .claude/hooks .claude/commands .claude/skills

    # Wiki sub-repo
    mkdir -p "wiki/${project}.wiki"
    (
        cd "wiki/${project}.wiki"
        git init --quiet --initial-branch=master
        git config user.email "test-user@example.test"
        git config user.name "Test User"
        # Minimal Home + index so the wiki isn't empty
        printf '%s\n' "---" "type: index" "up: \"\"" "---" "" "# Home (${project})" > "Home_${project}.md"
        printf '%s\n' "---" "type: index" "up: \"[[Home_${project}]]\"" "---" "" "# Index (${project})" > "index_${project}.md"

        # Minimal SCHEMA. Stage 2 amends with additional sections (CoALA,
        # status lifecycle, curator fields, directional inverses note).
        cat > "SCHEMA_${project}.md" <<SCHEMA_EOF
---
type: reference
up: "[[Home_${project}]]"
---

# Wiki Schema — ${project}

## Purpose

This wiki is a persistent, compounding knowledge base.

## Page Format

Every content page should include a title, body, and cross-references.

## Frontmatter

Every page gets standard YAML frontmatter with type: and up: fields.

## Naming Convention

Use Title-Case-Hyphenated.md for page files.

## Operations

The three operations are ingest, query, and lint.
SCHEMA_EOF

        git add . && git commit -q -m "initial empty wiki"
    )

    cd - >/dev/null
}

# Set up a second clone of the derivative's wiki, simulating a second machine
# or a second collaborator on the same machine. Returns the path.
init_second_clone() {
    local first="$1"
    local second="$2"
    cp -R "$first" "$second"
}

# Clone the real template into TARGET. Prefers MVP_TEMPLATE_LOCAL if set
# (offline mode), falls back to MVP_TEMPLATE_REPO (or DEFAULT_TEMPLATE_REPO).
# Returns 0 on success, 1 if both modes fail (e.g. no network and no local).
clone_template() {
    local target="$1"
    local repo="${MVP_TEMPLATE_REPO:-$DEFAULT_TEMPLATE_REPO}"
    local local_clone="${MVP_TEMPLATE_LOCAL:-}"

    if [ -n "$local_clone" ] && [ -d "$local_clone" ]; then
        # Local-clone mode: copy the working tree (preserving .git would
        # confuse instantiate.sh which expects to commit fresh state).
        # We re-init git so the derivative looks like a fresh checkout.
        cp -R "$local_clone" "$target"
        rm -rf "$target/.git"
        (
            cd "$target"
            git init --quiet --initial-branch=main
            git config user.email "smoke-test@example.test"
            git config user.name "Smoke Test"
            git add -A
            git commit -q -m "imported from local template clone for smoke test"
        )
        return 0
    fi

    # Network-clone mode
    if git clone --quiet "$repo" "$target" 2>/dev/null; then
        # Reset git config so commits made during the smoke test have a
        # known author.
        (
            cd "$target"
            git config user.email "smoke-test@example.test"
            git config user.name "Smoke Test"
        )
        return 0
    fi

    return 1
}

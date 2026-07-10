#!/usr/bin/env bash
# Patch: stage fixtures for the cursor-setup integration test.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/cursor-setup/ with:
#   checkout/  git repo whose basename ('checkout') deliberately differs
#              from its wiki name ('glyph'), to prove setup.sh takes the
#              name from the on-disk wiki, not the clone directory. Carries
#              a .cursorrules.template (for --legacy) and the four shipped
#              .cursor/rules/wiki-*.mdc.
#   nowiki/    git repo with no wiki/*.wiki (exercises the fail-loud path).
#
# The cursor overlay reuses the Claude Code overlay's CLAUDE.md snippet, so
# each fixture gets a copy of wiki/agents/claude-code/templates.

set -uo pipefail

STAGE="$SANDBOX/cursor-setup"

# patch.sh is executed, so locate the real repo from this file.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"

# Template-checkout guard: the fixtures need .cursorrules.template and
# .cursor/rules from the checkout, which instantiate consumes/prunes in
# derived projects (observed: 10 spurious fails in a derived project's
# CI). Decline WITHOUT creating $STAGE so assertions.sh skips cleanly.
# Discriminator matches clone_template's issue-#15 guard.
if [ ! -f "$REPO_ROOT/CLAUDE.md.template" ]; then
    echo "  cursor-setup: not a template checkout (derived project); declining to stage." >&2
    exit 0
fi
mkdir -p "$STAGE"
TPL_SRC="$REPO_ROOT/wiki/agents/claude-code/templates"
CURSORRULES_TPL="$REPO_ROOT/.cursorrules.template"
RULES_SRC="$REPO_ROOT/.cursor/rules"

# $1=project dir, $2=wiki name ('' = create no wiki)
_mkproj() {
    local dir="$1" wn="$2"
    git init -q "$dir"
    git -C "$dir" config user.email "cursor-test@example.test"
    git -C "$dir" config user.name  "cursor test"
    mkdir -p "$dir/wiki/agents/claude-code"
    cp -R "$TPL_SRC" "$dir/wiki/agents/claude-code/templates"
    if [ -n "$wn" ]; then
        mkdir -p "$dir/wiki/$wn.wiki"
        : > "$dir/wiki/$wn.wiki/SCHEMA_$wn.md"
    fi
    # CLAUDE.md with a Knowledge Graph anchor (snippet injects before it)
    # and no wiki-maintenance markers (so the injection actually runs).
    cat > "$dir/CLAUDE.md" <<'EOF'
# Project

Baseline content that must be preserved.

### Knowledge Graph

KG section.
EOF
}

_mkproj "$STAGE/checkout" "glyph"
# --legacy reads .cursorrules.template from the repo root.
cp "$CURSORRULES_TPL" "$STAGE/checkout/.cursorrules.template"
# Ship the four .cursor/rules/wiki-*.mdc so the rules check reports present.
mkdir -p "$STAGE/checkout/.cursor/rules"
cp "$RULES_SRC"/wiki-*.mdc "$STAGE/checkout/.cursor/rules/"

_mkproj "$STAGE/nowiki" ""

echo "  cursor-setup patch applied: fixtures at $STAGE"

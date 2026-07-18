#!/usr/bin/env bash
# Integration test patch: Cursor postToolUse advisory hook.
#
# Stages:
#   $SANDBOX/cursor-posttooluse-hook/hook.sh   — the posttooluse-hook.sh
#       template rendered with ${REPO_NAME}=fakerepo, for direct behaviour
#       testing (assertions.sh feeds it stdin fixtures).
#   $SANDBOX/cursor-posttooluse-hook/checkout/ — a fresh derived project (git
#       repo, wiki present, no .cursor/hooks.json yet) so assertions.sh can
#       run the real cursor/setup.sh --posttooluse-hook and verify it creates
#       the postToolUse registration from scratch (no jq needed on the fresh
#       path).
#
# Template-checkout guard mirrors cursor-setup: derived projects lack the
# claude-code templates / .cursor sources the fixture copies, so decline
# WITHOUT creating $STAGE and let assertions.sh skip cleanly.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
HOOK_TEMPLATE="$REPO_ROOT/wiki/agents/cursor/templates/posttooluse-hook.sh"

if [ ! -f "$REPO_ROOT/CLAUDE.md.template" ] || [ ! -f "$HOOK_TEMPLATE" ]; then
    echo "  cursor-posttooluse-hook: not a template checkout (or template missing); declining to stage." >&2
    exit 0
fi

STAGE="$SANDBOX/cursor-posttooluse-hook"
mkdir -p "$STAGE"

# --- Rendered hook for behaviour testing ---
sed 's/\${REPO_NAME}/fakerepo/g' "$HOOK_TEMPLATE" > "$STAGE/hook.sh"
chmod +x "$STAGE/hook.sh"

# --- Fresh derived project for the setup.sh --posttooluse-hook registration ---
TPL_SRC="$REPO_ROOT/wiki/agents/claude-code/templates"
RULES_SRC="$REPO_ROOT/.cursor/rules"
SKILLS_SRC="$REPO_ROOT/.cursor/skills"

DIR="$STAGE/checkout"
git init -q "$DIR"
git -C "$DIR" config user.email "cursor-ptu-test@example.test"
git -C "$DIR" config user.name  "cursor ptu test"
mkdir -p "$DIR/wiki/agents/claude-code"
cp -R "$TPL_SRC" "$DIR/wiki/agents/claude-code/templates"
mkdir -p "$DIR/wiki/glyph.wiki"
: > "$DIR/wiki/glyph.wiki/SCHEMA_glyph.md"
# setup.sh reads its own overlay templates from the real repo (via its own
# path), and the CLAUDE.md snippet from $REPO_ROOT/wiki/agents/claude-code/
# in the fixture (copied above). No cursor templates need staging here.
mkdir -p "$DIR/.cursor/rules"
cp "$RULES_SRC"/wiki-*.mdc "$DIR/.cursor/rules/"
mkdir -p "$DIR/.cursor/skills"
cp -R "$SKILLS_SRC"/. "$DIR/.cursor/skills/"
cat > "$DIR/CLAUDE.md" <<'EOF'
# Project

Baseline content.

### Knowledge Graph

KG section.
EOF

echo "  cursor-posttooluse-hook patch staged at $STAGE (rendered hook + fresh checkout)."

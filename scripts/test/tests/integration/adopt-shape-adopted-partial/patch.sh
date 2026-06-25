#!/usr/bin/env bash
# Patch: stage a host that hits exactly the 2-of-3 threshold for composite
# adoption detection. Companion to adopt-shape-adopted (3-of-3): this
# fixture proves that the count reported by the Status line is genuinely
# dynamic (computed from the actual signals) rather than hardcoded against
# the 3-of-3 case the other fixture exercises.
#
# Signals staged:
#   A: llm-wiki.md byte-identical to template      -> present
#   B: CLAUDE.md exists but DOES NOT contain the
#      lw:wiki-section sentinel                     -> absent
#   C: wiki/init-wiki.sh present                    -> present
#
# Result: 2 of 3 signals -> threshold met -> Status fires with
# '2 of 3 indicators matched', and signal B's bullet is absent from the
# Status block.
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-shape-adopted-partial"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/partial-host.git"

# Host-authored content (must survive untouched).
echo "# Partial Host"        > "$HOST/README.md"
echo "*.pyc"                 > "$HOST/.gitignore"

# Signal A: llm-wiki.md byte-identical to template.
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"

# Signal B intentionally OFF: CLAUDE.md exists but has plain host content
# without the lw:wiki-section sentinel. Simulates a host that authored its
# own CLAUDE.md without going through the agent overlay's setup, OR a
# project instantiated with --agent=none.
cat > "$HOST/CLAUDE.md" <<'EOF'
# Partial Host

This CLAUDE.md is entirely host-authored. No managed block, no sentinel.
The agent overlay was either skipped at instantiation time or this repo
predates the lw:wiki-section convention.

Project description, conventions, and notes for the LLM go here.
EOF

# Signal C: wiki/init-wiki.sh present (host-modified -> doubles as REFUSE
# target, same pattern as the 3-of-3 fixture).
mkdir -p "$HOST/wiki"
echo "# Host-modified init-wiki.sh — diverged from template" \
    > "$HOST/wiki/init-wiki.sh"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUTFILE="$STAGE/adopt-output.txt"

if ! bash "$ADOPT" --target="$HOST" > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

echo "  adopt-shape-adopted-partial patch applied: host at $HOST, output at $OUTFILE"

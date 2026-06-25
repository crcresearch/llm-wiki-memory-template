#!/usr/bin/env bash
# Patch: stage a host repo that has ALREADY adopted the wiki pattern, to
# exercise adopt.sh's composite 'already adopted' detection and the Status
# advice it surfaces.
#
# Detection uses three independent signals (>= 2 of 3 -> adopted):
#   A: llm-wiki.md byte-identical to template
#   B: <!-- lw:wiki-section --> sentinel inside CLAUDE.md
#   C: wiki/init-wiki.sh present in target
# This fixture deliberately stages all three so the report exercises the
# full Status block (3 of 3 indicators) AND so the wiki/init-wiki.sh REFUSE
# (host-modified) is concrete evidence behind the Status advice that
# overwriting via update-from-template.sh would discard local changes.
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-shape-adopted"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/adopted-host.git"

# Host-authored content (must survive untouched).
echo "# Adopted Host"        > "$HOST/README.md"
echo "*.pyc"                 > "$HOST/.gitignore"

# --- Signal A: llm-wiki.md byte-identical to template ---
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"

# --- Signal B: CLAUDE.md with the lw:wiki-section sentinel ---
# Host owns the rest of CLAUDE.md; the managed block is what the agent
# overlay's setup.sh would have injected. Adopt does not edit this file
# in stub mode; the sentinel is just the detection signal here.
cat > "$HOST/CLAUDE.md" <<'EOF'
# Adopted Host

Host-authored project guidance lives here. The block below is maintained
by the wiki overlay; it is a fenced region with the lw sentinel pair so
the host owner can delete it cleanly later if they choose.

<!-- lw:wiki-section -->
(content managed by adopt.sh in the future)
<!-- /lw:wiki-section -->

Anything after the closing sentinel is host-authored again.
EOF

# --- Signal C: wiki/init-wiki.sh present (and host-modified -> REFUSE) ---
# Doubles as the REFUSE target so the Status advice's "REFUSE entries
# below mark places where overwriting would discard local changes" is
# concretely demonstrated in the same report.
mkdir -p "$HOST/wiki"
echo "# Host-modified init-wiki.sh — do not let update-from-template silently overwrite" \
    > "$HOST/wiki/init-wiki.sh"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUTFILE="$STAGE/adopt-output.txt"

if ! bash "$ADOPT" --target="$HOST" > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

echo "  adopt-shape-adopted patch applied: host at $HOST, output at $OUTFILE"

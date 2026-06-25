#!/usr/bin/env bash
# Patch: stage a synthetic host repo to exercise adopt.sh classification.
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.
# Effects: creates $SANDBOX/adopt-shape/ with:
#   host/                  a real git repo with a fake origin slug
#                          (`example-host`) so lw_name_from_origin resolves
#                          to a predictable name, plus a small host-authored
#                          tree (README, .gitignore, src/main.py) to verify
#                          adopt does not confuse host content with template
#                          content.
#   host/llm-wiki.md       byte-identical copy of the template's file -> SKIP
#   host/wiki/agents/discipline-gates.md
#                          intentionally different content -> REFUSE
#   (rest of the ADD allowlist is absent in host -> ADD)
#   adopt-output.txt       captured stdout+stderr of adopt.sh --dry-run for
#                          the assertions to grep.
#
# Hermetic: adopt.sh in stub mode does not touch the network; identity comes
# from sandbox_git_env.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-shape"
HOST="$STAGE/host"
mkdir -p "$HOST"

# Real git repo with a fake origin. The owner is arbitrary; adopt.sh only
# parses the slug (`example-host`) via lw_name_from_origin. Same approach as
# the instantiate-naming smoke fixture.
git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/example-host.git"

# Host-authored content. With TOUCH grants not yet implemented, the stub
# doesn't print NEVER-TOUCH, but these files must survive untouched for the
# stub's "no writes to target" promise to be observable.
echo "# Example Host" > "$HOST/README.md"
echo "*.pyc"          > "$HOST/.gitignore"
mkdir -p "$HOST/src"
echo "print('hello')" > "$HOST/src/main.py"

# Pre-stage exactly one SKIP target (byte-identical to the template) and one
# REFUSE target (different content). Everything else in the ADD allowlist
# stays absent, so the dry-run reports it under ADD.
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"

mkdir -p "$HOST/wiki/agents"
echo "# Host-modified discipline gates (must not be overwritten)" \
    > "$HOST/wiki/agents/discipline-gates.md"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUTFILE="$STAGE/adopt-output.txt"

if ! bash "$ADOPT" --target="$HOST" > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

echo "  adopt-shape patch applied: host at $HOST, output at $OUTFILE"

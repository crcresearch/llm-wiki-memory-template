#!/usr/bin/env bash
# Patch: virgin host dry-run with --agent=cursor. Verifies classification
# includes TEMPLATE_OVERLAY_CURSOR paths and agent-gated default TOUCH
# (CLAUDE.md, .gitignore, .cursor/hooks.json — not .claude/settings.json).

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-shape-cursor"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/cursor-shape-host.git"

echo "# Cursor Shape Host" > "$HOST/README.md"
echo "*.pyc"               > "$HOST/.gitignore"

# No grants file: exercise agent-gated defaults for --agent=cursor.
# No adoption markers: virgin dry-run.

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUTFILE="$STAGE/adopt-output.txt"

if ! bash "$ADOPT" --target="$HOST" --agent=cursor > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh --agent=cursor exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

echo "  adopt-shape-cursor patch applied: host at $HOST, output at $OUTFILE"

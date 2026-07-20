#!/usr/bin/env bash
# Patch: virgin host --apply --agent=cursor with default (agent-gated)
# grants. Exercises ADD with {{REPO_NAME}} substitution, cursor setup,
# .cursor/hooks.json merge via --hook, and .cursorignore stamp.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-virgin-cursor"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/virgin-cursor-host.git"

echo "# Virgin Cursor Host" > "$HOST/README.md"
echo "*.pyc"                > "$HOST/.gitignore"

# No grants file; no adoption markers. Default agent grants for cursor.

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --apply --agent=cursor > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply --agent=cursor exited non-zero." >&2
    sed 's/^/    /' "$OUT" >&2
fi

echo "  adopt-apply-virgin-cursor patch applied: host at $HOST"

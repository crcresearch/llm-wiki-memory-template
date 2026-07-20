#!/usr/bin/env bash
# Patch: Claude-adopted host, then --force --agent=cursor to land the
# Cursor overlay on top (TIMELINE §3b). Verifies ADD of Cursor paths
# without destroying the existing Claude overlay.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-add-cursor-on-claude"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/claude-then-cursor.git"

echo "# Claude Then Cursor Host" > "$HOST/README.md"
echo "*.pyc"                     > "$HOST/.gitignore"

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"

# First: adopt as claude-code (virgin -> fully adopted).
OUT1="$STAGE/apply-claude.txt"
if ! bash "$ADOPT" --target="$HOST" --apply --agent=claude-code > "$OUT1" 2>&1; then
    echo "  WARN: first adopt --agent=claude-code exited non-zero." >&2
    sed 's/^/    /' "$OUT1" >&2
fi

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "after claude adopt"

# Second: force-adopt Cursor overlay onto the Claude host.
OUT2="$STAGE/apply-cursor.txt"
if ! bash "$ADOPT" --target="$HOST" --apply --force --agent=cursor > "$OUT2" 2>&1; then
    echo "  WARN: adopt --force --agent=cursor exited non-zero." >&2
    sed 's/^/    /' "$OUT2" >&2
fi

echo "  adopt-apply-add-cursor-on-claude patch applied: host at $HOST"

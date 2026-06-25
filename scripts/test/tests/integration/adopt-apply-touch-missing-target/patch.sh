#!/usr/bin/env bash
# Patch: virgin host with grants referencing files that don't exist on
# disk. Exercises the TOUCH_MISSING classification path: the grant is
# valid (target known, type known) but the file isn't there, so adopt
# should classify the grant as moot and surface it in GRANT WARNINGS,
# not in TOUCH applied.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-touch-missing-target"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/missing-target-host.git"

echo "# Missing Target Host" > "$HOST/README.md"
echo "*.pyc"                 > "$HOST/.gitignore"

# Grant references CLAUDE.md and .claude/settings.json but the host has
# NEITHER. Both should be reported as 'granted but absent in host'.
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  CLAUDE.md:              managed-block
  .claude/settings.json:  merge
EOF

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply exited non-zero." >&2
fi

echo "  adopt-apply-touch-missing-target patch applied: host at $HOST"

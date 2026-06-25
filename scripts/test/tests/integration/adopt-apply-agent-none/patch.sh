#!/usr/bin/env bash
# Patch: virgin host with CLAUDE.md and managed-block grant, but the
# user passes --agent=none. Overlay setup should be skipped entirely
# and the managed-block TOUCH should be reported as 'skipped' (not
# applied via setup.sh, not failed).

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-agent-none"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/agent-none-host.git"

cat > "$HOST/CLAUDE.md" <<'EOF'
# Agent None Host

Host runs adopt with --agent=none. Overlay setup must NOT be invoked
and managed-block TOUCH must NOT inject sentinels.

## Project conventions

These must survive unchanged.
EOF
echo "*.pyc" > "$HOST/.gitignore"

# Both grants present to verify both managed-block (depends on overlay)
# and merge (depends on overlay) record 'skipped' with the right reason.
mkdir -p "$HOST/.claude"
cat > "$HOST/.claude/settings.json" <<'EOF'
{"theme": "host"}
EOF
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  CLAUDE.md:              managed-block
  .claude/settings.json:  merge
EOF

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --agent=none --apply > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply --agent=none exited non-zero." >&2
fi

echo "  adopt-apply-agent-none patch applied: host at $HOST"

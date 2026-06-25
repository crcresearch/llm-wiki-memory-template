#!/usr/bin/env bash
# Patch: virgin host with a CLAUDE.md that does NOT contain the
# '### Knowledge Graph' anchor. Exercises the overlay setup.sh's
# fallback path where lw_inject_block, finding no anchor, appends
# the sentinel-paired block at end-of-file instead.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-virgin-no-anchor"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/no-anchor-host.git"

# CLAUDE.md without the overlay's KG anchor anywhere -- not as heading,
# not as quoted prose. (Even an in-prose mention would let grep -F match,
# so the fallback path would never trigger.) Plain host prose only.
cat > "$HOST/CLAUDE.md" <<'EOF'
# No Anchor Host

This CLAUDE.md is intentionally short and carries none of the overlay
anchors. The overlay setup should fall back to EOF append.

## Conventions

Host-authored conventions go here.

LAST_HOST_LINE
EOF

echo "*.pyc" > "$HOST/.gitignore"

cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  CLAUDE.md:  managed-block
EOF

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply exited non-zero." >&2
fi

echo "  adopt-apply-virgin-no-anchor patch applied: host at $HOST"

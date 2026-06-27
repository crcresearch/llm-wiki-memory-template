#!/usr/bin/env bash
# Patch: virgin host with one granted target ABSENT on disk. Exercises
# the TOUCH_MISSING classification path: the grant is valid (target
# known, type known) but the file isn't there, so adopt should classify
# the grant as moot and surface it in GRANT WARNINGS, not in TOUCH
# applied.
#
# A second grant points at CLAUDE.md, which DOES exist in the host -- it
# anchors the fixture to a fully-working Phase 2B (init-wiki + overlay
# setup) so we can also assert that adopt completed (manifest written)
# and that the absent file was NOT silently created.

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

# CLAUDE.md PRESENT: the managed-block grant has a target, so it
# classifies as TOUCH, not MISSING. This keeps init-wiki from having to
# seed CLAUDE.md from scratch (orthogonal Phase-2B path that has had
# platform-specific quirks); the fixture stays focused on what it is
# testing: the MISSING classification for .claude/settings.json.
cat > "$HOST/CLAUDE.md" <<'EOF'
# Missing Target Host

Host CLAUDE.md is committed so adopt's Phase 2B overlay setup has a
target to patch. The grant under test is for .claude/settings.json,
which is intentionally NOT present on disk.

### Knowledge Graph

(A trivial anchor so overlay setup injects its sentinels into the
expected position; not the focus of this fixture.)
EOF

# Single grant targeting an absent file. Keeping the grants file to a
# single MISSING entry keeps the fixture focused on TOUCH_MISSING and
# avoids interaction with the CLAUDE.md / overlay setup path (which is
# already covered by adopt-apply-virgin-with-claude).
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
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

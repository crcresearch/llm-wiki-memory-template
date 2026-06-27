#!/usr/bin/env bash
# Patch: stage a host with TOUCH grants and run adopt.sh --apply (Phase 2A:
# append-only TOUCH apply).
#
# Verifies:
#  - .gitignore gets a sentinel-paired lw:wiki-rules block at the end,
#    with the canonical wiki/*.wiki/ rule inside.
#  - The host's prior .gitignore content is preserved verbatim above the
#    new block.
#  - managed-block and merge grants are classified but reported as
#    deferred (Phase 2B / Phase 3) in the manifest.
#  - Re-running --apply is idempotent: lw_inject_block detects the
#    opening sentinel and returns 'already-present' instead of
#    duplicating the block.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-touch"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/touch-host.git"

# Host-authored content (must survive untouched above any TOUCH block).
cat > "$HOST/README.md" <<'EOF'
# Touch Host
Host-authored README.
EOF

cat > "$HOST/.gitignore" <<'EOF'
# Host's own gitignore content
*.pyc
__pycache__/
.env
EOF

# Host CLAUDE.md so the managed-block grant is TOUCH (not MISSING) and the
# manifest can report it as 'deferred -- Phase 2B' rather than skip it.
cat > "$HOST/CLAUDE.md" <<'EOF'
# Touch Host
Host-authored project guidance.
EOF

# Host .claude/settings.json so the merge grant is TOUCH (not MISSING) and
# the manifest can report it as 'deferred -- Phase 3'.
mkdir -p "$HOST/.claude"
cat > "$HOST/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash"]
  }
}
EOF

# Pre-stage Signal A and Signal C so adopt classifies the host as adopted
# (composite threshold met) and proceeds with the apply.
cp "$TEMPLATE_ROOT/llm-wiki.md" "$HOST/llm-wiki.md"
mkdir -p "$HOST/wiki"
cp "$TEMPLATE_ROOT/wiki/init-wiki.sh" "$HOST/wiki/init-wiki.sh"

# Grants file covering all three TOUCH types so the test exercises each
# branch of the apply-mode dispatch.
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  .gitignore:             append-only
  CLAUDE.md:              managed-block
  .claude/settings.json:  merge
EOF

# Commit so the working tree is clean (adopt's safety guard refuses
# --apply otherwise).
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"

# --- First --apply run ---
# This fixture stages Signal A (llm-wiki.md byte-equal) + Signal C
# (wiki/init-wiki.sh present) so the composite detector says 'adopted'
# from the start. --force keeps the apply path exercised; this test is
# about the TOUCH apply mechanics, not the advisory-abort behaviour
# (which has its own test, adopt-apply-blocked).
OUT1="$STAGE/apply-run1.txt"
if ! bash "$ADOPT" --target="$HOST" --apply --force > "$OUT1" 2>&1; then
    echo "  WARN: first adopt.sh --apply --force exited non-zero." >&2
    sed 's/^/    /' "$OUT1" >&2
fi

# --- Second --apply run --force (idempotency on the lw_inject_block path) ---
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "after first apply" \
    >/dev/null 2>&1 || true   # may be empty if first run had no effect

OUT2="$STAGE/apply-run2.txt"
if ! bash "$ADOPT" --target="$HOST" --apply --force > "$OUT2" 2>&1; then
    echo "  WARN: second adopt.sh --apply --force exited non-zero." >&2
    sed 's/^/    /' "$OUT2" >&2
fi

echo "  adopt-apply-touch patch applied: host at $HOST"

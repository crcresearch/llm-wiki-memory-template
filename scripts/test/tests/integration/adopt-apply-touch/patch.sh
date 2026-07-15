#!/usr/bin/env bash
# Patch: stage a host with TOUCH grants and run adopt.sh --apply.
#
# Verifies:
#  - The host's .gitignore is never modified: the wiki sub-repo ignore
#    rule arrives as the ADDed wiki/.gitignore instead.
#  - managed-block and merge grants are classified and applied via the
#    overlay setup.sh (Phase 2B / Phase 3).
#  - Re-running --apply is idempotent: the overlay's lw_inject_block
#    detects existing sentinels and the host .gitignore stays
#    byte-identical across both runs.

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

# Grants file covering both TOUCH types so the test exercises each
# branch of the apply-mode dispatch.
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  CLAUDE.md:              managed-block
  .claude/settings.json:  merge
EOF

# Snapshot the host's .gitignore: assertions prove it survives BOTH
# --apply runs byte-identical (adopt must never modify it).
cp "$HOST/.gitignore" "$STAGE/gitignore.before"

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

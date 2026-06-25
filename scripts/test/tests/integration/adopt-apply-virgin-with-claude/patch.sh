#!/usr/bin/env bash
# Patch: stage a VIRGIN host (composite < 2 of 3 signals) that already
# has its own CLAUDE.md and a grants file granting managed-block on it.
# This exercises the realistic case "project has its own CLAUDE.md and
# wants to take on the wiki-memory pattern".
#
# adopt --apply on this host should:
#   - run Phase 1 ADD (host has none of the template files)
#   - run Phase 2B init-wiki (creates wiki sub-repo)
#   - run Phase 2B overlay setup (injects sentinel-paired blocks INTO
#     the host's existing CLAUDE.md WITHOUT destroying its prose)
#   - record managed-block TOUCH as applied via setup.sh
#
# No --force needed; the host starts as virgin.

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-apply-virgin-with-claude"
HOST="$STAGE/host"
mkdir -p "$HOST"

git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/virgin-claude-host.git"

# Host-authored content. CLAUDE.md has prose ABOVE and BELOW where the
# overlay's managed blocks will land; both segments must survive the
# injection unchanged.
cat > "$HOST/README.md" <<'EOF'
# Virgin Claude Host
A project that has its own CLAUDE.md and is taking on the wiki pattern.
EOF

cat > "$HOST/CLAUDE.md" <<'EOF'
# Virgin Claude Host

This CLAUDE.md was authored by the project owner before adoption.
It has its own conventions, style notes, and project-specific rules.

## Wiki

(The overlay's setup.sh will inject sentinel-paired blocks here.)

### Knowledge Graph

(Anchor where the overlay's lw:wiki-maintenance block lands BEFORE.)

## Project conventions

These conventions are host-authored and must survive adoption unchanged.
EOF

echo "*.pyc" > "$HOST/.gitignore"

# Grants file: managed-block on CLAUDE.md so adopt records the TOUCH
# (and Phase 2B's invocation of setup.sh actually does the injection).
cat > "$HOST/.llm-wiki-adopt-grants.yml" <<'EOF'
grants:
  CLAUDE.md:  managed-block
EOF

# Crucially: do NOT stage llm-wiki.md, discipline-gates.md, or
# wiki/init-wiki.sh. That keeps the composite detector at 0 of 3 so
# adopt sees this as a virgin host and proceeds with --apply.

git -C "$HOST" -c user.email=test@x.invalid -c user.name=test add -A
git -C "$HOST" -c user.email=test@x.invalid -c user.name=test commit -q -m "initial host content"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUT="$STAGE/apply-output.txt"
if ! bash "$ADOPT" --target="$HOST" --apply > "$OUT" 2>&1; then
    echo "  WARN: adopt.sh --apply exited non-zero." >&2
    sed 's/^/    /' "$OUT" >&2
fi

echo "  adopt-apply-virgin-with-claude patch applied: host at $HOST"

#!/usr/bin/env bash
# Patch: stage a host repo that has ALREADY adopted the wiki pattern, to
# exercise the 'already adopted' detection in adopt.sh and the Status
# advice it surfaces.
#
# Inputs:  SANDBOX env var (from run.sh); git identity from sandbox_git_env.
# Effects: creates $SANDBOX/adopt-shape-adopted/ with:
#   host/                       a real git repo with origin slug 'adopted-host'
#   host/.llm-wiki-template-log.md   the marker instantiate.sh would write
#   host/wiki/adopted-host.wiki/.git an initialized wiki sub-repo (init-wiki
#                                    marker; uses lw_name_from_origin's slug)
#   host/wiki/init-wiki.sh           host-modified file -> REFUSE, so the
#                                    Status advice about overwriting REFUSE
#                                    entries is concretely demonstrated
#   adopt-output.txt            captured stdout+stderr of adopt.sh --dry-run

set -uo pipefail

HERE_PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE_PATCH/../../../../.." && pwd)"

STAGE="$SANDBOX/adopt-shape-adopted"
HOST="$STAGE/host"
mkdir -p "$HOST"

# Real git repo with a fake origin slug. lw_name_from_origin resolves to
# 'adopted-host'; the wiki sub-repo path uses the same slug.
git init -q "$HOST"
git -C "$HOST" remote add origin "https://github.com/example-org/adopted-host.git"

# Host content (untouched by adopt).
echo "# Adopted Host"        > "$HOST/README.md"
echo "*.pyc"                 > "$HOST/.gitignore"

# Marker #1: instantiate.sh would write this file on first instantiation.
cat > "$HOST/.llm-wiki-template-log.md" <<'EOF'
# Template sync log

## 2026-05-01: initial instantiation (synthetic)
- template version: synthetic
EOF

# Marker #3: the wiki sub-repo, initialized at wiki/<slug>.wiki/.
mkdir -p "$HOST/wiki/adopted-host.wiki"
git init -q "$HOST/wiki/adopted-host.wiki"

# Host has a modified copy of one template file -> REFUSE. The Status advice
# refers to this case explicitly ("REFUSE entries below mark places where
# overwriting would discard local changes"), so the test verifies the
# advice is honest about a real situation present in the same report.
mkdir -p "$HOST/wiki"
echo "# Host-modified init-wiki.sh — do not let update-from-template silently overwrite" \
    > "$HOST/wiki/init-wiki.sh"

ADOPT="$TEMPLATE_ROOT/scripts/adopt.sh"
OUTFILE="$STAGE/adopt-output.txt"

if ! bash "$ADOPT" --target="$HOST" > "$OUTFILE" 2>&1; then
    echo "  WARN: adopt.sh exited non-zero; assertions will surface the cause." >&2
    sed 's/^/    /' "$OUTFILE" >&2
fi

echo "  adopt-shape-adopted patch applied: host at $HOST, output at $OUTFILE"

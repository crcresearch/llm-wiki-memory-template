#!/usr/bin/env bash
# Scenario 01: two agents add different new pages.
# Expected: both pages present; index has both entries; log has both entries.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../../sandbox.sh
source "$PROTO_DIR/sandbox.sh"
# shellcheck source=../../protocol.sh
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

noop_resolve() {
    echo "BUG: scenario 01 should not need semantic resolution; got $2" >&2
    exit 1
}

changes_A() {
    local wiki="$1"
    cat > "$wiki/Topic-Alpha.md" <<'EOF'
# Topic Alpha

Authored by agent A (csweet1).
EOF
    echo "- [Topic-Alpha](Topic-Alpha)" >> "$wiki/index_proto.md"
    echo "" >> "$wiki/log_proto.md"
    echo "## [2026-05-31] ingest | A added Topic-Alpha" >> "$wiki/log_proto.md"
    git -C "$wiki" add Topic-Alpha.md index_proto.md log_proto.md
}

changes_B() {
    local wiki="$1"
    cat > "$wiki/Topic-Beta.md" <<'EOF'
# Topic Beta

Authored by agent B (vardeman).
EOF
    echo "- [Topic-Beta](Topic-Beta)" >> "$wiki/index_proto.md"
    echo "" >> "$wiki/log_proto.md"
    echo "## [2026-05-31] ingest | B added Topic-Beta" >> "$wiki/log_proto.md"
    git -C "$wiki" add Topic-Beta.md index_proto.md log_proto.md
}

echo "Scenario 01: different pages"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
agent_write "$A_WIKI" "csweet1" changes_A noop_resolve "A: add Topic-Alpha" || { echo "FAIL: A write" >&2; exit 1; }
agent_write "$B_WIKI" "vardeman" changes_B noop_resolve "B: add Topic-Beta" || { echo "FAIL: B write" >&2; exit 1; }

# Verify final state
VERIFY="$(clone_for_agent verify)"
fail=0
[ -f "$VERIFY/Topic-Alpha.md" ] || { echo "FAIL: Topic-Alpha.md missing"; fail=$((fail+1)); }
[ -f "$VERIFY/Topic-Beta.md" ]  || { echo "FAIL: Topic-Beta.md missing"; fail=$((fail+1)); }
grep -qE 'Topic-Alpha' "$VERIFY/index_proto.md" || { echo "FAIL: index lacks Topic-Alpha"; fail=$((fail+1)); }
grep -qE 'Topic-Beta' "$VERIFY/index_proto.md"  || { echo "FAIL: index lacks Topic-Beta"; fail=$((fail+1)); }
grep -qE 'A added Topic-Alpha' "$VERIFY/log_proto.md" || { echo "FAIL: log lacks A entry"; fail=$((fail+1)); }
grep -qE 'B added Topic-Beta' "$VERIFY/log_proto.md"  || { echo "FAIL: log lacks B entry"; fail=$((fail+1)); }

if [ $fail -eq 0 ]; then
    echo "PASS: scenario 01"
    exit 0
else
    echo "FAIL: scenario 01 ($fail assertions failed)"
    exit 1
fi

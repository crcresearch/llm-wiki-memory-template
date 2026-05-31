#!/usr/bin/env bash
# Scenario 05: two agents both append log entries.
# Expected: both entries present after union merge.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

noop_resolve() {
    echo "BUG: scenario 05 should not need semantic resolution; got $2" >&2
    cat "$1/$2" >&2
    exit 1
}

changes_A() {
    local wiki="$1"
    cat >> "$wiki/log_proto.md" <<'EOF'

## [2026-05-31] ingest | A: filed Topic-A
- by: csweet1 via claude-code
- A's notes.
EOF
    git -C "$wiki" add log_proto.md
}

changes_B() {
    local wiki="$1"
    cat >> "$wiki/log_proto.md" <<'EOF'

## [2026-05-31] ingest | B: filed Topic-B
- by: vardeman via claude-code
- B's notes.
EOF
    git -C "$wiki" add log_proto.md
}

echo "Scenario 05: log union append"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
agent_write "$A_WIKI" "csweet1" changes_A noop_resolve "A: log entry" || { echo "FAIL: A write" >&2; exit 1; }
agent_write "$B_WIKI" "vardeman" changes_B noop_resolve "B: log entry" || { echo "FAIL: B write" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
grep -qE 'A: filed Topic-A' "$VERIFY/log_proto.md" || { echo "FAIL: A log entry missing"; fail=$((fail+1)); }
grep -qE 'B: filed Topic-B' "$VERIFY/log_proto.md" || { echo "FAIL: B log entry missing"; fail=$((fail+1)); }
if grep -qE '<<<<<<<|>>>>>>>' "$VERIFY/log_proto.md"; then
    echo "FAIL: conflict markers leaked into log"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 05"; exit 0; else echo "FAIL: scenario 05 ($fail)"; exit 1; fi

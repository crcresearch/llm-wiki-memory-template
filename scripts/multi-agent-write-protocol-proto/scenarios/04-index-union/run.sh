#!/usr/bin/env bash
# Scenario 04: two agents both append new index entries.
# Expected: both entries present after union merge (no semantic resolver).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

noop_resolve() {
    echo "BUG: scenario 04 should not need semantic resolution; got $2" >&2
    cat "$1/$2" >&2
    exit 1
}

changes_A() {
    local wiki="$1"
    echo "- [Topic-A-Index](Topic-A-Index): added by agent A" >> "$wiki/index_proto.md"
    git -C "$wiki" add index_proto.md
}

changes_B() {
    local wiki="$1"
    echo "- [Topic-B-Index](Topic-B-Index): added by agent B" >> "$wiki/index_proto.md"
    git -C "$wiki" add index_proto.md
}

echo "Scenario 04: index union merge"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
agent_write "$A_WIKI" "csweet1" changes_A noop_resolve "A: index entry" || { echo "FAIL: A write" >&2; exit 1; }
agent_write "$B_WIKI" "vardeman" changes_B noop_resolve "B: index entry" || { echo "FAIL: B write" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
grep -qE 'Topic-A-Index' "$VERIFY/index_proto.md" || { echo "FAIL: A index entry missing"; fail=$((fail+1)); }
grep -qE 'Topic-B-Index' "$VERIFY/index_proto.md" || { echo "FAIL: B index entry missing"; fail=$((fail+1)); }
if grep -qE '<<<<<<<|>>>>>>>' "$VERIFY/index_proto.md"; then
    echo "FAIL: conflict markers leaked into index"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 04"; exit 0; else echo "FAIL: scenario 04 ($fail)"; exit 1; fi

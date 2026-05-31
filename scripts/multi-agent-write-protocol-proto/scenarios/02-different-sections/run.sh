#!/usr/bin/env bash
# Scenario 02: two agents edit different sections of the same page.
# Expected: both edits present via three-way merge; no semantic resolution.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

# Seed Welcome.md with multiple sections.
git -C "$SANDBOX/main" pull --quiet
cat > "$SANDBOX/main/Welcome.md" <<'EOF'
# Welcome

Intro paragraph.

## Method

(method placeholder)

## Results

(results placeholder)

## Discussion

(discussion placeholder)
EOF
git -C "$SANDBOX/main" add Welcome.md
git -C "$SANDBOX/main" commit -m "Seed Welcome with sections" --quiet
git -C "$SANDBOX/main" push --quiet

noop_resolve() {
    echo "BUG: scenario 02 should not need semantic resolution; got $2" >&2
    cat "$1/$2" >&2
    exit 1
}

changes_A() {
    local wiki="$1"
    # Edit the Method section
    awk '
        /^## Method/ { in_method=1; print; print ""; print "Method by agent A: derived from first-principles."; next }
        /^## / && in_method { in_method=0 }
        in_method && /^\(method placeholder\)$/ { next }
        { print }
    ' "$wiki/Welcome.md" > "$wiki/Welcome.md.new"
    mv "$wiki/Welcome.md.new" "$wiki/Welcome.md"
    git -C "$wiki" add Welcome.md
}

changes_B() {
    local wiki="$1"
    # Edit the Results section
    awk '
        /^## Results/ { in_res=1; print; print ""; print "Results by agent B: measured on test corpus."; next }
        /^## / && in_res { in_res=0 }
        in_res && /^\(results placeholder\)$/ { next }
        { print }
    ' "$wiki/Welcome.md" > "$wiki/Welcome.md.new"
    mv "$wiki/Welcome.md.new" "$wiki/Welcome.md"
    git -C "$wiki" add Welcome.md
}

echo "Scenario 02: different sections of same page"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"
agent_write "$A_WIKI" "csweet1" changes_A noop_resolve "A: edit Method" || { echo "FAIL: A write" >&2; exit 1; }
agent_write "$B_WIKI" "vardeman" changes_B noop_resolve "B: edit Results" || { echo "FAIL: B write" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
grep -qE 'Method by agent A' "$VERIFY/Welcome.md" || { echo "FAIL: Method section lacks A's edit"; fail=$((fail+1)); }
grep -qE 'Results by agent B' "$VERIFY/Welcome.md" || { echo "FAIL: Results section lacks B's edit"; fail=$((fail+1)); }
grep -qE 'Discussion' "$VERIFY/Welcome.md" || { echo "FAIL: Discussion section gone"; fail=$((fail+1)); }
if grep -qE '<<<<<<<|>>>>>>>' "$VERIFY/Welcome.md"; then
    echo "FAIL: conflict markers leaked into final state"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 02"; exit 0; else echo "FAIL: scenario 02 ($fail)"; exit 1; fi

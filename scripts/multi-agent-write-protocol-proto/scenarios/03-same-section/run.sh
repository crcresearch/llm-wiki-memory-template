#!/usr/bin/env bash
# Scenario 03: two agents edit the same section (semantic conflict).
# Uses prepare/publish interleaving so B's working branch is rooted at
# the pre-A origin/main; B's publish then sees A's commit on origin/main
# and the merge produces a genuine conflict.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

# Seed Welcome.md with a single Conclusion section.
git -C "$SANDBOX/main" pull --quiet
cat > "$SANDBOX/main/Welcome.md" <<'EOF'
# Welcome

## Conclusion

(conclusion placeholder)
EOF
git -C "$SANDBOX/main" add Welcome.md
git -C "$SANDBOX/main" commit -m "Seed Welcome with Conclusion" --quiet
git -C "$SANDBOX/main" push --quiet

# B's deterministic semantic resolver: take A's content and append B's
# below it under an "### Update by agent-B" sub-section.
resolve_B() {
    local wiki="$1"
    local file="$2"
    # In a git merge conflict, <<<<<<< HEAD is the local side (B's
    # working-branch commit) and >>>>>>> origin/main is the incoming side
    # (A's already-pushed commit). For our "adapt" policy, we keep A's
    # version as the canonical body and append B's beneath under a header.
    awk '
        /^<<<<<<< / { in_local=1; in_incoming=0; next }
        /^=======$/ && in_local { in_local=0; in_incoming=1; next }
        /^>>>>>>> / && in_incoming { in_incoming=0; next }
        in_local    { local_content = local_content $0 ORS; next }
        in_incoming { incoming_content = incoming_content $0 ORS; next }
        { print }
        END {
            printf("%s", incoming_content)
            print ""
            print "### Update by agent-B (vardeman)"
            print ""
            printf("%s", local_content)
        }
    ' "$wiki/$file" > "$wiki/$file.merged"
    mv "$wiki/$file.merged" "$wiki/$file"
}

changes_A() {
    local wiki="$1"
    cat > "$wiki/Welcome.md" <<'EOF'
# Welcome

## Conclusion

A's strong conclusion: the wiki pattern compounds across sessions.
EOF
    git -C "$wiki" add Welcome.md
}

changes_B() {
    local wiki="$1"
    cat > "$wiki/Welcome.md" <<'EOF'
# Welcome

## Conclusion

B's cautious conclusion: subject to validation in multi-user use.
EOF
    git -C "$wiki" add Welcome.md
}

noop() { echo "BUG: A should not hit resolver"; exit 1; }

echo "Scenario 03: same section, semantic resolution"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"

# Both agents prepare against the same base. A publishes first; B then
# publishes and hits the conflict.
agent_prepare "$A_WIKI" "csweet1"  changes_A "A: write Conclusion" >/dev/null || { echo "FAIL: A prepare" >&2; exit 1; }
agent_prepare "$B_WIKI" "vardeman" changes_B "B: write Conclusion" >/dev/null || { echo "FAIL: B prepare" >&2; exit 1; }
agent_publish "$A_WIKI" "csweet1"  noop      || { echo "FAIL: A publish" >&2; exit 1; }
agent_publish "$B_WIKI" "vardeman" resolve_B || { echo "FAIL: B publish" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
grep -qE "A's strong conclusion" "$VERIFY/Welcome.md" || { echo "FAIL: A's content missing"; fail=$((fail+1)); }
grep -qE "B's cautious conclusion" "$VERIFY/Welcome.md" || { echo "FAIL: B's content missing"; fail=$((fail+1)); }
grep -qE "Update by agent-B" "$VERIFY/Welcome.md" || { echo "FAIL: resolver header missing"; fail=$((fail+1)); }
if grep -qE '<<<<<<<|>>>>>>>' "$VERIFY/Welcome.md"; then
    echo "FAIL: conflict markers leaked"; fail=$((fail+1))
fi
a_line=$(grep -n "A's strong conclusion" "$VERIFY/Welcome.md" | cut -d: -f1)
b_line=$(grep -n "B's cautious conclusion" "$VERIFY/Welcome.md" | cut -d: -f1)
if [ -n "$a_line" ] && [ -n "$b_line" ] && [ "$a_line" -ge "$b_line" ]; then
    echo "FAIL: B's content should appear below A's (A@$a_line, B@$b_line)"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 03"; exit 0; else echo "FAIL: scenario 03 ($fail)"; exit 1; fi

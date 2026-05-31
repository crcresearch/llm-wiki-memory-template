#!/usr/bin/env bash
# Scenario 07: livelock / retry cap.
# A pre-receive hook on origin always rejects pushes. With
# AGENT_MAX_RETRIES=1 the protocol gets 2 attempts before halting.
# Verifies return code = 2 and the agent branch is preserved.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO_DIR="$(cd "$HERE/../.." && pwd)"
source "$PROTO_DIR/sandbox.sh"
source "$PROTO_DIR/protocol.sh"

setup_sandbox
trap cleanup_sandbox EXIT

HOOK_DIR="$SANDBOX/origin.git/hooks"
COUNTER="$SANDBOX/.push_counter"
echo 0 > "$COUNTER"
cat > "$HOOK_DIR/pre-receive" <<HOOK
#!/usr/bin/env bash
counter=\$(cat "$COUNTER")
counter=\$((counter + 1))
echo \$counter > "$COUNTER"
echo "Mock reject: simulating persistent livelock (attempt \$counter)" >&2
exit 1
HOOK
chmod +x "$HOOK_DIR/pre-receive"

noop_resolve() {
    echo "BUG: scenario 07 should not need semantic resolution; got $2" >&2
    exit 1
}

changes_B() {
    local wiki="$1"
    cat > "$wiki/Topic-Livelock.md" <<'EOF'
# Topic Livelock

B's write that origin will reject persistently.
EOF
    git -C "$wiki" add Topic-Livelock.md
}

echo "Scenario 07: livelock retry cap"
B_WIKI="$(clone_for_agent B)"
AGENT_MAX_RETRIES=1
set +e
agent_write "$B_WIKI" "vardeman" changes_B noop_resolve "B: livelock write"
rc=$?
set -e

fail=0
if [ "$rc" -ne 2 ]; then
    echo "FAIL: expected exit code 2 (halted at cap); got $rc"
    fail=$((fail+1))
fi
total_pushes=$(cat "$COUNTER")
# AGENT_MAX_RETRIES=1 → 2 total attempts → 2 push attempts → 2 hook rejections.
if [ "$total_pushes" -ne 2 ]; then
    echo "FAIL: expected 2 push attempts; got $total_pushes"
    fail=$((fail+1))
fi
# Branch preserved for inspection.
branches=$(git -C "$B_WIKI" branch --list 'agent/vardeman/*' | wc -l | tr -d ' ')
if [ "$branches" -lt 1 ]; then
    echo "FAIL: agent branch not preserved for inspection"
    fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 07"; exit 0; else echo "FAIL: scenario 07 ($fail)"; exit 1; fi

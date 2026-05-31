#!/usr/bin/env bash
# Scenario 06: push race.
# Setup: a pre-receive hook on the bare origin rejects exactly the
# second push attempt (which we know is B's first push). All other pushes
# pass through. With prepare/publish ordering: A.publish (push 1, allowed),
# B.publish (push 2 attempt 1, rejected → retry → push 3, allowed).
#
# Verifies that the protocol detects the rejection, refetches and retries
# without intervention, and both contributions land.

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
if [ "\$counter" -eq 2 ]; then
    echo "Mock reject: simulating push race on attempt \$counter" >&2
    exit 1
fi
exit 0
HOOK
chmod +x "$HOOK_DIR/pre-receive"

noop_resolve() {
    echo "BUG: scenario 06 should not need semantic resolution; got $2" >&2
    exit 1
}

changes_A() {
    local wiki="$1"
    cat > "$wiki/Topic-Race-A.md" <<'EOF'
# Topic Race A

Authored by A in the race scenario.
EOF
    git -C "$wiki" add Topic-Race-A.md
}

changes_B() {
    local wiki="$1"
    cat > "$wiki/Topic-Race-B.md" <<'EOF'
# Topic Race B

Authored by B in the race scenario.
EOF
    git -C "$wiki" add Topic-Race-B.md
}

echo "Scenario 06: push race"
A_WIKI="$(clone_for_agent A)"
B_WIKI="$(clone_for_agent B)"

# Both prepare; A publishes first; B's publish hits the mock reject once
# and the protocol's retry loop pushes again successfully.
agent_prepare "$A_WIKI" "csweet1"  changes_A "A: race write" >/dev/null || { echo "FAIL: A prepare" >&2; exit 1; }
agent_prepare "$B_WIKI" "vardeman" changes_B "B: race write" >/dev/null || { echo "FAIL: B prepare" >&2; exit 1; }
agent_publish "$A_WIKI" "csweet1"  noop_resolve || { echo "FAIL: A publish" >&2; exit 1; }
agent_publish "$B_WIKI" "vardeman" noop_resolve || { echo "FAIL: B publish" >&2; exit 1; }

VERIFY="$(clone_for_agent verify)"
fail=0
[ -f "$VERIFY/Topic-Race-A.md" ] || { echo "FAIL: A's page missing"; fail=$((fail+1)); }
[ -f "$VERIFY/Topic-Race-B.md" ] || { echo "FAIL: B's page missing"; fail=$((fail+1)); }
# Counter reflects total push attempts: 1 (A) + 2 (B initial + B retry) = 3.
total_pushes=$(cat "$COUNTER")
if [ "$total_pushes" -ne 3 ]; then
    echo "FAIL: expected 3 push attempts (A + B initial + B retry); got $total_pushes"
    fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "PASS: scenario 06"; exit 0; else echo "FAIL: scenario 06 ($fail)"; exit 1; fi

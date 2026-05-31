#!/usr/bin/env bash
# Stage 1 (agent identity) assertions.
# Sourced by run.sh. SANDBOX is set by the caller; assertion helpers from lib/assert.sh.

D="$SANDBOX/derivative"

# --- Structural: files exist ---
assert ".claude/agent-id file exists" "[ -f '$D/.claude/agent-id' ]"
assert ".claude/hooks/session-start.sh is executable" "[ -x '$D/.claude/hooks/session-start.sh' ]"

# --- Content: agent-id ---
assert_contains "agent-id contains a claude-<human>@<project> handle" \
    "$D/.claude/agent-id" \
    "^claude-[a-zA-Z0-9_.-]+@"

# --- commit-msg hook installed correctly ---
assert "commit-msg hook installed" "[ -f '$D/.git/hooks/commit-msg' ]"
assert "commit-msg hook is executable" "[ -x '$D/.git/hooks/commit-msg' ]"
assert_contains "commit-msg hook is the trailer-injector" \
    "$D/.git/hooks/commit-msg" \
    "agent-trailer-injector"

# --- Behavioral: a commit picks up both trailers ---
(
    cd "$D"
    echo "test content for stage 1" > stage1-test.txt
    git add stage1-test.txt
    git commit -q -m "stage 1 test commit"
)
LAST_COMMIT_MSG=$(git -C "$D" log -1 --format=%B)

if echo "$LAST_COMMIT_MSG" | grep -q "Co-Authored-By: Claude Code"; then
    echo "  PASS: commit message has Co-Authored-By trailer"
    PASS=$((PASS+1))
else
    echo "  FAIL: commit message has Co-Authored-By trailer"
    echo "    last commit message was:"
    echo "$LAST_COMMIT_MSG" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("commit message has Co-Authored-By trailer")
fi

if echo "$LAST_COMMIT_MSG" | grep -q "Agent-Instance:"; then
    echo "  PASS: commit message has Agent-Instance trailer"
    PASS=$((PASS+1))
else
    echo "  FAIL: commit message has Agent-Instance trailer"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("commit message has Agent-Instance trailer")
fi

# --- Instance ID: stable across runs on same path ---
INST1=$(cd "$D" && bash .claude/hooks/session-start.sh 2>&1 | awk '/^Instance:/ {print $2}')
INST2=$(cd "$D" && bash .claude/hooks/session-start.sh 2>&1 | awk '/^Instance:/ {print $2}')
assert_eq "instance ID is stable across two runs on same path" "$INST1" "$INST2"

# --- Instance ID: varies with path ---
# Set up a second clone at a different path; same wiki, same code, different location.
init_second_clone "$D" "$SANDBOX/derivative-clone2"
INST3=$(cd "$SANDBOX/derivative-clone2" && bash .claude/hooks/session-start.sh 2>&1 | awk '/^Instance:/ {print $2}')
assert_ne "instance ID varies with checkout path" "$INST1" "$INST3"

# --- Handle: stable across runs ---
H1=$(cd "$D" && bash .claude/hooks/session-start.sh 2>&1 | awk '/^Agent identity:/ {print $3}')
H2=$(cd "$D" && bash .claude/hooks/session-start.sh 2>&1 | awk '/^Agent identity:/ {print $3}')
assert_eq "handle is stable across two runs on same project" "$H1" "$H2"

# --- Handle: read from .claude/agent-id, not recomputed when file present ---
# Override with a custom handle in the file; the hook should respect it.
echo "claude-customhandle@my-project" > "$D/.claude/agent-id"
HCUSTOM=$(cd "$D" && bash .claude/hooks/session-start.sh 2>&1 | awk '/^Agent identity:/ {print $3}')
assert_eq "hook respects custom handle from .claude/agent-id" "claude-customhandle@my-project" "$HCUSTOM"

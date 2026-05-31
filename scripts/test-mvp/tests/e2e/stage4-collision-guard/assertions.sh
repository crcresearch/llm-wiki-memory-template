#!/usr/bin/env bash
# Stage 4 (pre-push collision guard) assertions.

D="$SANDBOX/derivative"
WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
WIKI_REMOTE="$SANDBOX/wiki-remote.git"

# --- Pre-push hook installed ---
assert "pre-push hook installed in wiki repo" \
    "[ -f '$WIKI_DIR/.git/hooks/pre-push' ]"
assert "pre-push hook is executable" \
    "[ -x '$WIKI_DIR/.git/hooks/pre-push' ]"
assert_contains "pre-push hook is the collision-guard" \
    "$WIKI_DIR/.git/hooks/pre-push" "wiki-push-collision-guard"

# --- Ensure local and remote are in sync before the scenarios ---
# Discard any divergence left by prior stages (Stage 3's tests leave local
# and remote on sibling commits). This guarantees Scenario A genuinely
# starts from "no divergence" so the clean-push test exercises the
# fast-path through the pre-push hook (exit 0 with no rebase activity).
if git -C "$WIKI_DIR" rev-parse --quiet --verify origin/master >/dev/null 2>&1; then
    ( cd "$WIKI_DIR" && git fetch -q origin && git reset --hard origin/master 2>/dev/null || true )
fi

# --- Scenario A: Clean push (no divergence) -----------------------------
(
    cd "$WIKI_DIR"
    echo "stage-4 clean push test" > Stage-4-Clean.md
    git add Stage-4-Clean.md
    git commit -q -m "stage 4: clean push"
)
CLEAN_OUT=$( cd "$WIKI_DIR" && git push origin master 2>&1 ) && CLEAN_RC=0 || CLEAN_RC=$?
assert_eq "clean push (no divergence) succeeds" "0" "$CLEAN_RC"

# --- Scenario B: Push when behind, non-conflicting (rebase succeeds; push needs retry) ---
# Important: git push resolves refs BEFORE the pre-push hook fires. Even on
# successful rebase, the first push fails ("fetch first" rejection from
# the remote), the hook prints "Re-run 'git push' to publish", and the user
# pushes again. The second push is a clean fast-forward and succeeds.
SIDE="$SANDBOX/wiki-side-clone-stage4"
rm -rf "$SIDE"
git clone --quiet "$WIKI_REMOTE" "$SIDE"
(
    cd "$SIDE"
    git config user.email "side@example.test"
    git config user.name "Side Collaborator"
    echo "side commit content" > Side-Commit.md
    git add Side-Commit.md
    git commit -q -m "side: non-conflicting commit"
    git push -q origin master
)

(
    cd "$WIKI_DIR"
    echo "local non-conflicting" > Local-Non-Conflicting.md
    git add Local-Non-Conflicting.md
    git commit -q -m "local: non-conflicting commit"
)

# First push: rebase happens in hook, then hook aborts push (exit 1)
LOCAL_HEAD_BEFORE=$(git -C "$WIKI_DIR" rev-parse HEAD)
PUSH1_OUT=$( cd "$WIKI_DIR" && git push origin master 2>&1 ) && PUSH1_RC=0 || PUSH1_RC=$?
assert_ne "first push (behind+rebaseable) fails as expected, prompting retry" "0" "$PUSH1_RC"

if echo "$PUSH1_OUT" | grep -qiE "rebasing|Rebase clean"; then
    echo "  PASS: first push triggers rebase activity in pre-push output"
    PASS=$((PASS+1))
else
    echo "  FAIL: first push triggers rebase activity in pre-push output"
    echo "    push output was:"
    echo "$PUSH1_OUT" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("first push triggers rebase activity")
fi

if echo "$PUSH1_OUT" | grep -q "Re-run 'git push'"; then
    echo "  PASS: first push instructs the user to re-run git push"
    PASS=$((PASS+1))
else
    echo "  FAIL: first push instructs the user to re-run git push"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("first push instructs user to re-run")
fi

# Local HEAD should have advanced (rebased) even though push failed
LOCAL_HEAD_AFTER_REBASE=$(git -C "$WIKI_DIR" rev-parse HEAD)
assert_ne "local HEAD moved after rebase (despite first-push abort)" "$LOCAL_HEAD_BEFORE" "$LOCAL_HEAD_AFTER_REBASE"

# Second push: clean fast-forward, succeeds
PUSH2_OUT=$( cd "$WIKI_DIR" && git push origin master 2>&1 ) && PUSH2_RC=0 || PUSH2_RC=$?
assert_eq "second push succeeds (exit 0)" "0" "$PUSH2_RC"

LOCAL_HEAD=$(git -C "$WIKI_DIR" rev-parse HEAD)
REMOTE_HEAD=$(git -C "$WIKI_DIR" rev-parse "@{u}")
assert_eq "after second push, local HEAD = remote HEAD" "$LOCAL_HEAD" "$REMOTE_HEAD"

# --- Scenario C: Push with conflict (rebase fails, push aborts) ---
(
    cd "$SIDE"
    git pull -q --ff-only origin master
    echo "side version of shared file" > Shared-File.md
    git add Shared-File.md
    git commit -q -m "side: edits Shared-File"
    git push -q origin master
)

(
    cd "$WIKI_DIR"
    # Do NOT pull. Make a conflicting local commit.
    echo "local version of shared file" > Shared-File.md
    git add Shared-File.md
    git commit -q -m "local: also edits Shared-File"
)

CONFLICT_OUT=$( cd "$WIKI_DIR" && git push origin master 2>&1 ) && CONFLICT_RC=0 || CONFLICT_RC=$?
assert_ne "conflicting push fails (exit non-zero)" "0" "$CONFLICT_RC"

if echo "$CONFLICT_OUT" | grep -q "BLOCKED: push aborted"; then
    echo "  PASS: conflicting push prints BLOCKED message"
    PASS=$((PASS+1))
else
    echo "  FAIL: conflicting push prints BLOCKED message"
    echo "    push output was:"
    echo "$CONFLICT_OUT" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("conflicting push prints BLOCKED message")
fi

if echo "$CONFLICT_OUT" | grep -q "Shared-File"; then
    echo "  PASS: BLOCKED message lists the conflicting file"
    PASS=$((PASS+1))
else
    echo "  FAIL: BLOCKED message lists the conflicting file"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("BLOCKED message lists conflicting file")
fi

if echo "$CONFLICT_OUT" | grep -q "Manual resolution needed"; then
    echo "  PASS: BLOCKED message includes recovery sequence"
    PASS=$((PASS+1))
else
    echo "  FAIL: BLOCKED message includes recovery sequence"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("BLOCKED message includes recovery sequence")
fi

# --- Cleanup state check: rebase aborted cleanly, no stuck state ---
assert "wiki repo not stuck in rebase state after abort" \
    "[ ! -d '$WIKI_DIR/.git/rebase-merge' ] && [ ! -d '$WIKI_DIR/.git/rebase-apply' ]"

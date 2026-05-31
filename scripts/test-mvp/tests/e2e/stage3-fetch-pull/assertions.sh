#!/usr/bin/env bash
# Stage 3 (SessionStart fetch + auto-pull) assertions.

D="$SANDBOX/derivative"
WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
PROJECT_NAME=$(basename "$WIKI_DIR" .wiki)
WIKI_REMOTE="$SANDBOX/wiki-remote.git"

# --- Script content ---
assert_contains "session-start.sh has wiki fetch logic" \
    "$D/.claude/hooks/session-start.sh" "fetch --quiet"
assert_contains "session-start.sh has auto-pull logic" \
    "$D/.claude/hooks/session-start.sh" "pull --ff-only --quiet"
assert_contains "session-start.sh has divergence fallback message" \
    "$D/.claude/hooks/session-start.sh" "Manual resolution needed"

# --- Helper: run SessionStart and capture combined output ---
run_session_start() {
    ( cd "$D" && bash .claude/hooks/session-start.sh 2>&1 )
}

# --- Up-to-date case ---
OUT1=$(run_session_start)
if echo "$OUT1" | grep -q "Wiki is up to date"; then
    echo "  PASS: session-start reports up-to-date when no incoming"
    PASS=$((PASS+1))
else
    echo "  FAIL: session-start reports up-to-date when no incoming"
    echo "    output was:"
    echo "$OUT1" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("session-start reports up-to-date when no incoming")
fi

# --- Simulate an incoming commit via a side clone of the bare remote ---
SIDE="$SANDBOX/wiki-side-clone"
rm -rf "$SIDE"
git clone --quiet "$WIKI_REMOTE" "$SIDE"
(
    cd "$SIDE"
    git config user.email "side-collaborator@example.test"
    git config user.name "Side Collaborator"
    echo "incoming content" > "Incoming-Page.md"
    git add Incoming-Page.md
    git commit -q -m "incoming commit from a collaborator"
    git push -q origin master
)

# --- Incoming case: fetch + report + auto-pull ---
OUT2=$(run_session_start)

if echo "$OUT2" | grep -q "Wiki has 1 incoming commit"; then
    echo "  PASS: session-start reports incoming commit count"
    PASS=$((PASS+1))
else
    echo "  FAIL: session-start reports incoming commit count"
    echo "    output was:"
    echo "$OUT2" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("session-start reports incoming commit count")
fi

if echo "$OUT2" | grep -q "Auto-pulled"; then
    echo "  PASS: session-start auto-pulls when fast-forward possible"
    PASS=$((PASS+1))
else
    echo "  FAIL: session-start auto-pulls when fast-forward possible"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("session-start auto-pulls when ff possible")
fi

# After auto-pull, local HEAD should equal remote HEAD
LOCAL_HEAD=$(git -C "$WIKI_DIR" rev-parse HEAD)
REMOTE_HEAD=$(git -C "$WIKI_DIR" rev-parse "@{u}")
assert_eq "after auto-pull, local HEAD = remote HEAD" "$LOCAL_HEAD" "$REMOTE_HEAD"

# --- Subsequent run reports up-to-date again ---
OUT3=$(run_session_start)
if echo "$OUT3" | grep -q "Wiki is up to date"; then
    echo "  PASS: second session-start (after pull) reports up-to-date"
    PASS=$((PASS+1))
else
    echo "  FAIL: second session-start (after pull) reports up-to-date"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("second session-start reports up-to-date after pull")
fi

# --- Divergence case: local has an unpushed commit AND remote has new commits ---
# Local commit (not pushed)
(
    cd "$WIKI_DIR"
    echo "local-only content" > "Local-Only-Page.md"
    git add Local-Only-Page.md
    git commit -q -m "local-only commit"
)

# Remote commit via the side clone
(
    cd "$SIDE"
    git pull -q origin master   # catch up
    echo "more incoming" > "Second-Incoming.md"
    git add Second-Incoming.md
    git commit -q -m "second incoming commit"
    git push -q origin master
)

OUT4=$(run_session_start)

if echo "$OUT4" | grep -q "Could not auto-pull"; then
    echo "  PASS: session-start detects divergence and reports fallback"
    PASS=$((PASS+1))
else
    echo "  FAIL: session-start detects divergence and reports fallback"
    echo "    output was:"
    echo "$OUT4" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("session-start detects divergence and reports fallback")
fi

if echo "$OUT4" | grep -qE "git -C .* pull --rebase"; then
    echo "  PASS: divergence message includes recovery hint"
    PASS=$((PASS+1))
else
    echo "  FAIL: divergence message includes recovery hint"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("divergence message includes recovery hint")
fi

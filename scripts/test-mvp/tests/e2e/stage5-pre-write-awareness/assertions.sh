#!/usr/bin/env bash
# Stage 5 (mid-session pre-write awareness) assertions.

D="$SANDBOX/derivative"
WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
WIKI_REMOTE="$SANDBOX/wiki-remote.git"
HOOK="$D/.claude/hooks/pre-write-fetch.sh"

# --- Files installed ---
assert "pre-write-fetch.sh exists" "[ -f '$HOOK' ]"
assert "pre-write-fetch.sh is executable" "[ -x '$HOOK' ]"
assert "/wiki-status command file exists" "[ -f '$D/.claude/commands/wiki-status.md' ]"
assert_contains "wiki-status command references git fetch" \
    "$D/.claude/commands/wiki-status.md" "git -C .* fetch"

# --- jq availability gate ---
if ! command -v jq >/dev/null 2>&1; then
    skip "behavioral assertions" "jq not installed (Stage 5 hook requires jq)"
    return 0 2>/dev/null || true
fi

# --- Defensive: hook always exits 0 ---
RC_EMPTY=$(echo "" | "$HOOK" >/dev/null 2>&1; echo $?)
assert_eq "hook exits 0 on empty stdin (defensive)" "0" "$RC_EMPTY"

RC_NOFP=$(echo '{"tool_name":"Edit","tool_input":{}}' | "$HOOK" >/dev/null 2>&1; echo $?)
assert_eq "hook exits 0 when file_path is missing (defensive)" "0" "$RC_NOFP"

# --- Behavioral: align local with remote first so we have a clean baseline ---
if git -C "$WIKI_DIR" rev-parse --quiet --verify origin/master >/dev/null 2>&1; then
    ( cd "$WIKI_DIR" && git fetch -q origin && git reset --hard origin/master 2>/dev/null || true )
fi

# --- Up-to-date case: hook is silent ---
WIKI_FILE="$WIKI_DIR/Test-Page.md"
INPUT_WIKI=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$WIKI_FILE")
OUT_UP=$(echo "$INPUT_WIKI" | "$HOOK" 2>&1 || true)
if [ -z "$OUT_UP" ]; then
    echo "  PASS: hook is silent when wiki is up to date"
    PASS=$((PASS+1))
else
    echo "  FAIL: hook is silent when wiki is up to date"
    echo "    output was:"
    echo "$OUT_UP" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("hook silent when up to date")
fi

# --- Set up an incoming commit via a side clone ---
SIDE="$SANDBOX/wiki-side-stage5"
rm -rf "$SIDE"
git clone --quiet "$WIKI_REMOTE" "$SIDE"
(
    cd "$SIDE"
    git config user.email "side@example.test"
    git config user.name "Side Collaborator"
    echo "stage 5 incoming content" > Stage-5-Incoming-Page.md
    git add Stage-5-Incoming-Page.md
    git commit -q -m "stage 5: incoming page from side"
    git push -q origin master
)

# --- Wiki-path edit: hook reports incoming ---
OUT_INC=$(echo "$INPUT_WIKI" | "$HOOK" 2>&1 || true)

if echo "$OUT_INC" | grep -q "incoming changes"; then
    echo "  PASS: hook reports incoming when editing a wiki file"
    PASS=$((PASS+1))
else
    echo "  FAIL: hook reports incoming when editing a wiki file"
    echo "    output was:"
    echo "$OUT_INC" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("hook reports incoming on wiki path")
fi

if echo "$OUT_INC" | grep -q "Stage-5-Incoming-Page"; then
    echo "  PASS: incoming report includes affected page names"
    PASS=$((PASS+1))
else
    echo "  FAIL: incoming report includes affected page names"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("incoming report includes page names")
fi

if echo "$OUT_INC" | grep -q "side-collaborator\|Side Collaborator"; then
    echo "  PASS: incoming report includes author"
    PASS=$((PASS+1))
else
    echo "  FAIL: incoming report includes author"
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("incoming report includes author")
fi

# --- Non-wiki path: hook is silent (path filter holds) ---
NON_WIKI_FILE="$D/scripts/some-file.sh"
mkdir -p "$(dirname "$NON_WIKI_FILE")"
touch "$NON_WIKI_FILE"
INPUT_NONWIKI=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$NON_WIKI_FILE")
OUT_NONWIKI=$(echo "$INPUT_NONWIKI" | "$HOOK" 2>&1 || true)
if [ -z "$OUT_NONWIKI" ]; then
    echo "  PASS: hook is silent on non-wiki file Edit (path filter holds)"
    PASS=$((PASS+1))
else
    echo "  FAIL: hook is silent on non-wiki file Edit (path filter holds)"
    echo "    output was:"
    echo "$OUT_NONWIKI" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("hook silent on non-wiki file")
fi

# --- Hook always exits 0 even when reporting (non-blocking) ---
RC_REPORT=$(echo "$INPUT_WIKI" | "$HOOK" >/dev/null 2>&1; echo $?)
assert_eq "hook exits 0 even when surfacing incoming (non-blocking)" "0" "$RC_REPORT"

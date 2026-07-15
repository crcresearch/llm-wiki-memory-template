#!/usr/bin/env bash
# Integration test assertions: Cursor sessionStart hook JSON injection.
#
# Runs the rendered hook against both fake projects staged by patch.sh
# and asserts on the JSON additional_context payload.

STAGE_DIR="$SANDBOX/cursor-session-start-hook"
FAKE_DIR="$STAGE_DIR/fakerepo"
NOWIKI_DIR="$STAGE_DIR/fakerepo-nowiki"

if [ ! -d "$FAKE_DIR" ] || [ ! -f "$FAKE_DIR/hook.sh" ]; then
    skip "cursor-session-start-hook integration assertions" "fakerepo staging missing"
    return 0 2>/dev/null || true
fi

# Cursor sends sessionStart input JSON on stdin; empty object is enough.
HOOK_IN='{"session_id":"test","is_background_agent":false,"composer_mode":"agent"}'

WITH_WIKI_OUT=$(cd "$FAKE_DIR" && printf '%s' "$HOOK_IN" | bash hook.sh 2>&1)
WITH_WIKI_OUT_FILE=$(mktemp)
printf '%s\n' "$WITH_WIKI_OUT" > "$WITH_WIKI_OUT_FILE"

assert "cursor hook stdout is valid JSON" \
    "python3 -c \"import json,sys; json.load(open('$WITH_WIKI_OUT_FILE'))\""

CTX_FILE=$(mktemp)
python3 -c "import json; print(json.load(open('$WITH_WIKI_OUT_FILE'))['additional_context'])" > "$CTX_FILE"

assert_contains "cursor hook additional_context has orientation" \
    "$CTX_FILE" "durable memory"
assert_contains "cursor hook orientation mentions wiki/<repo>.wiki/" \
    "$CTX_FILE" "wiki/fakerepo.wiki/"
assert "cursor hook does NOT leak \${REPO_NAME}" \
    "! grep -qF '\${REPO_NAME}' '$CTX_FILE'"
assert_contains "cursor hook emits index injection header" \
    "$CTX_FILE" "## Wiki current state — index"
assert_contains "cursor hook emits the index's sentinel page entry" \
    "$CTX_FILE" "Test-Concept-Alpha"
assert_contains "cursor hook emits last-log-entries header" \
    "$CTX_FILE" "## Wiki current state — last 5 log entries"
assert "cursor hook does NOT include log Entry 1" \
    "! grep -qF 'Entry 1 — oldest' '$CTX_FILE'"
assert_contains "cursor hook includes log Entry 3 (first of last-5)" \
    "$CTX_FILE" "Entry 3 — first of the last 5"
assert_contains "cursor hook includes log Entry 7 (most recent)" \
    "$CTX_FILE" "Entry 7 — most recent"
assert_contains "cursor hook mentions project skills (not slash commands)" \
    "$CTX_FILE" "wiki-experiment"

rm -f "$WITH_WIKI_OUT_FILE" "$CTX_FILE"

if [ -f "$NOWIKI_DIR/hook.sh" ]; then
    NOWIKI_OUT=$(cd "$NOWIKI_DIR" && printf '%s' "$HOOK_IN" | bash hook.sh 2>&1)
    NOWIKI_OUT_FILE=$(mktemp)
    printf '%s\n' "$NOWIKI_OUT" > "$NOWIKI_OUT_FILE"
    NOWIKI_CTX=$(mktemp)
    python3 -c "import json; print(json.load(open('$NOWIKI_OUT_FILE'))['additional_context'])" > "$NOWIKI_CTX"

    assert_contains "no-wiki: cursor hook still emits orientation" \
        "$NOWIKI_CTX" "durable memory"
    assert "no-wiki: cursor hook does NOT emit index header" \
        "! grep -qF 'Wiki current state — index' '$NOWIKI_CTX'"
    assert "no-wiki: cursor hook does NOT emit log header" \
        "! grep -qF 'Wiki current state — last 5' '$NOWIKI_CTX'"
    NOWIKI_RC=$(cd "$NOWIKI_DIR" && printf '%s' "$HOOK_IN" | bash hook.sh >/dev/null 2>&1; echo $?)
    assert_eq "no-wiki: cursor hook exits 0" "0" "$NOWIKI_RC"

    rm -f "$NOWIKI_OUT_FILE" "$NOWIKI_CTX"
fi

#!/usr/bin/env bash
# Integration test assertions: Cursor postToolUse advisory hook.
#
# Two concerns:
#   1. Behaviour of the rendered hook — a Write/Edit to a wiki page yields an
#      additional_context nudge naming both gate files; a non-wiki path yields
#      an empty additional_context. Always valid JSON, always exit 0.
#   2. setup.sh --posttooluse-hook installs the script and registers it under
#      postToolUse with matcher "Write|Edit" (fresh hooks.json, no jq needed).

STAGE="$SANDBOX/cursor-posttooluse-hook"

if [ ! -f "$STAGE/hook.sh" ]; then
    skip "cursor-posttooluse-hook assertions" "fixture staging missing (derived project or template absent)"
    return 0 2>/dev/null || true
fi
if ! command -v python3 >/dev/null 2>&1; then
    skip "cursor-posttooluse-hook assertions" "python3 not available"
    return 0 2>/dev/null || true
fi

# --- 1. Behaviour: wiki-page write -> gate nudge -------------------------------
WIKI_IN='{"tool_name":"Write","tool_input":{"file_path":"wiki/fakerepo.wiki/Foo.md"}}'
WIKI_OUT=$(printf '%s' "$WIKI_IN" | bash "$STAGE/hook.sh" 2>&1)
WIKI_OUT_FILE=$(mktemp)
printf '%s\n' "$WIKI_OUT" > "$WIKI_OUT_FILE"

assert "posttooluse hook stdout is valid JSON (wiki write)" \
    "python3 -c \"import json; json.load(open('$WIKI_OUT_FILE'))\""

WIKI_CTX=$(mktemp)
python3 -c "import json; print(json.load(open('$WIKI_OUT_FILE'))['additional_context'])" > "$WIKI_CTX"

assert_contains "posttooluse nudge references discipline-gates.md" \
    "$WIKI_CTX" "wiki/agents/discipline-gates.md"
assert_contains "posttooluse nudge references verification-gate.md" \
    "$WIKI_CTX" "wiki/agents/verification-gate.md"
assert_contains "posttooluse nudge states it does not block" \
    "$WIKI_CTX" "does not block"
assert_contains "posttooluse nudge names the index page (REPO_NAME substituted)" \
    "$WIKI_CTX" "index_fakerepo.md"
assert "posttooluse nudge does NOT leak \${REPO_NAME}" \
    "! grep -qF '\${REPO_NAME}' '$WIKI_CTX'"

WIKI_RC=$(printf '%s' "$WIKI_IN" | bash "$STAGE/hook.sh" >/dev/null 2>&1; echo $?)
assert_eq "posttooluse hook exits 0 on wiki write" "0" "$WIKI_RC"

rm -f "$WIKI_OUT_FILE" "$WIKI_CTX"

# --- 1b. Behaviour: non-wiki write -> empty additional_context ----------------
NONWIKI_IN='{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}'
NONWIKI_OUT=$(printf '%s' "$NONWIKI_IN" | bash "$STAGE/hook.sh" 2>&1)
NONWIKI_OUT_FILE=$(mktemp)
printf '%s\n' "$NONWIKI_OUT" > "$NONWIKI_OUT_FILE"

assert "posttooluse hook stdout is valid JSON (non-wiki write)" \
    "python3 -c \"import json; json.load(open('$NONWIKI_OUT_FILE'))\""
assert "posttooluse hook emits empty additional_context for non-wiki path" \
    "[ -z \"\$(python3 -c \"import json; print(json.load(open('$NONWIKI_OUT_FILE'))['additional_context'])\")\" ]"
NONWIKI_RC=$(printf '%s' "$NONWIKI_IN" | bash "$STAGE/hook.sh" >/dev/null 2>&1; echo $?)
assert_eq "posttooluse hook exits 0 on non-wiki write" "0" "$NONWIKI_RC"

rm -f "$NONWIKI_OUT_FILE"

# --- 2. setup.sh --posttooluse-hook: install + fresh registration -------------
if [ -d "$STAGE/checkout" ]; then
    # assertions.sh is sourced by run.sh, so $HERE = scripts/test/; two up = repo root.
    REPO_ROOT_PTU="$(cd "$HERE/../.." && pwd)"
    SETUP="$REPO_ROOT_PTU/wiki/agents/cursor/setup.sh"

    ( cd "$STAGE/checkout" && bash "$SETUP" --posttooluse-hook ) >/dev/null 2>&1

    assert "setup: posttooluse-hook.sh installed and executable" \
        "[ -x '$STAGE/checkout/.cursor/hooks/posttooluse-hook.sh' ]"
    assert "setup: posttooluse-hook.sh rendered with the wiki name (no \${REPO_NAME} leak)" \
        "! grep -qF '\${REPO_NAME}' '$STAGE/checkout/.cursor/hooks/posttooluse-hook.sh'"
    assert "setup: hooks.json created with postToolUse registration" \
        "[ -f '$STAGE/checkout/.cursor/hooks.json' ] && grep -qF 'postToolUse' '$STAGE/checkout/.cursor/hooks.json'"
    assert "setup: hooks.json registers the posttooluse hook command" \
        "grep -qF '.cursor/hooks/posttooluse-hook.sh' '$STAGE/checkout/.cursor/hooks.json'"
    assert "setup: hooks.json carries the Write|Edit matcher" \
        "grep -qF 'Write|Edit' '$STAGE/checkout/.cursor/hooks.json'"
    assert "setup: hooks.json is valid JSON" \
        "python3 -c \"import json; json.load(open('$STAGE/checkout/.cursor/hooks.json'))\""

    # Idempotency: a re-run skips the existing script + registration.
    OUT_PTU="$( cd "$STAGE/checkout" && bash "$SETUP" --posttooluse-hook 2>&1 )"
    PTU_SKIP=0; case "$OUT_PTU" in *"posttooluse-hook.sh: already present"*) PTU_SKIP=1 ;; esac
    assert "setup: re-run skips existing posttooluse-hook.sh" "[ $PTU_SKIP -eq 1 ]"
    PTU_JSON_SKIP=0; case "$OUT_PTU" in *"postToolUse advisory hook already registered"*) PTU_JSON_SKIP=1 ;; esac
    assert "setup: re-run skips existing postToolUse registration" "[ $PTU_JSON_SKIP -eq 1 ]"
fi

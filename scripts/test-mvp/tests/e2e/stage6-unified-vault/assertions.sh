#!/usr/bin/env bash
# Stage 6 (unified-vault protection) assertions.

D="$SANDBOX/derivative"
WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
PROJECT_NAME=$(basename "$WIKI_DIR" .wiki)
SCHEMA_FILE="$WIKI_DIR/SCHEMA_${PROJECT_NAME}.md"
LINT="$D/scripts/wiki-lint-check.sh"

# --- SCHEMA has the namespacing section ---
assert_contains "SCHEMA has Namespacing for unified personal vaults section" \
    "$SCHEMA_FILE" "^## Namespacing for unified personal vaults"
assert_contains "SCHEMA namespacing section lists nav artifacts" \
    "$SCHEMA_FILE" "Home_<project>.md"

# --- Lint still applies Stage 2 status-aware checks ---
# (Regression: rerunning Stage 2's test cases should still behave correctly.)
mkpage() {
    local name="$1"; local content="$2"
    printf '%s' "$content" > "$WIKI_DIR/${name}.md"
}

mkpage "Stage6-Canonical-Valid" "---
type: concept
up: \"[[Home_${PROJECT_NAME}]]\"
---

A valid canonical page; should still pass after Stage 6 extends the lint.
"
assert "Stage 2 regression: canonical page still passes" \
    "$LINT '$WIKI_DIR/Stage6-Canonical-Valid.md'"

# --- Nav-page namespacing: properly-suffixed pages pass ---
assert "properly-suffixed Home_<project>.md passes lint" \
    "$LINT '$WIKI_DIR/Home_${PROJECT_NAME}.md'"
assert "properly-suffixed index_<project>.md passes lint" \
    "$LINT '$WIKI_DIR/index_${PROJECT_NAME}.md'"

# --- Nav-page namespacing: unsuffixed nav files are flagged ---
mkpage "index" "---
type: index
up: \"\"
---

This index.md is not project-suffixed and should be flagged.
"
LINT_OUT=$( "$LINT" "$WIKI_DIR/index.md" 2>&1 ) && RC=0 || RC=$?
assert_ne "unsuffixed index.md fails lint" "0" "$RC"
if echo "$LINT_OUT" | grep -qi "not project-suffixed"; then
    echo "  PASS: unsuffixed index.md error message mentions 'not project-suffixed'"
    PASS=$((PASS+1))
else
    echo "  FAIL: unsuffixed index.md error message mentions 'not project-suffixed'"
    echo "    output was:"
    echo "$LINT_OUT" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("unsuffixed index.md error mentions namespacing")
fi

mkpage "SCHEMA" "---
type: reference
up: \"[[Home_${PROJECT_NAME}]]\"
---

Stub schema, unsuffixed; should be flagged.
"
LINT_SCHEMA_OUT=$( "$LINT" "$WIKI_DIR/SCHEMA.md" 2>&1 ) && SCHEMA_RC=0 || SCHEMA_RC=$?
assert_ne "unsuffixed SCHEMA.md fails lint" "0" "$SCHEMA_RC"

# --- Home.md: minimal redirect bridge allowed, substantive content flagged ---
mkpage "Home" "---
type: index
up: \"\"
---

See [Home_${PROJECT_NAME}](Home_${PROJECT_NAME}).
"
assert "Home.md as a minimal redirect bridge passes lint" \
    "$LINT '$WIKI_DIR/Home.md'"

# Now make Home.md substantive (>300 chars body) and verify it gets flagged
BIG_BODY=$(printf 'This is a substantive Home page with lots of content. %.0s' {1..15})
mkpage "Home" "---
type: index
up: \"\"
---

${BIG_BODY}
"
LINT_HOME_OUT=$( "$LINT" "$WIKI_DIR/Home.md" 2>&1 ) && HOME_RC=0 || HOME_RC=$?
assert_ne "Home.md with substantive content fails lint" "0" "$HOME_RC"
if echo "$LINT_HOME_OUT" | grep -qi "redirect bridge"; then
    echo "  PASS: substantive Home.md error message mentions 'redirect bridge'"
    PASS=$((PASS+1))
else
    echo "  FAIL: substantive Home.md error message mentions 'redirect bridge'"
    echo "    output was:"
    echo "$LINT_HOME_OUT" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("substantive Home.md error mentions redirect bridge")
fi

# --- Two project wikis side-by-side: nav pages don't collide ---
# Simulate by creating a second project's namespaced nav pages alongside
# the first and verifying both pass lint.
mkpage "Home_OtherProject" "---
type: index
up: \"\"
---

Other project home page.
"
mkpage "index_OtherProject" "---
type: index
up: \"[[Home_OtherProject]]\"
---

Other project index.
"
assert "second project's Home_<other>.md coexists without conflict" \
    "$LINT '$WIKI_DIR/Home_OtherProject.md'"
assert "second project's index_<other>.md coexists without conflict" \
    "$LINT '$WIKI_DIR/index_OtherProject.md'"

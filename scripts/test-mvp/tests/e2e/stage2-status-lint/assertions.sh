#!/usr/bin/env bash
# Stage 2 (status-aware frontmatter + relaxed lint) assertions.
# Sourced by run.sh. SANDBOX is set by the caller; assertion helpers from lib/assert.sh.

D="$SANDBOX/derivative"
WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
PROJECT_NAME=$(basename "$WIKI_DIR" .wiki)
SCHEMA_FILE="$WIKI_DIR/SCHEMA_${PROJECT_NAME}.md"
LINT="$D/scripts/wiki-lint-check.sh"

# --- SCHEMA additions present ---
assert_contains "SCHEMA has Cognitive architecture section" \
    "$SCHEMA_FILE" "^## Cognitive architecture"
assert_contains "SCHEMA has Page status lifecycle section" \
    "$SCHEMA_FILE" "^## Page status lifecycle"
assert_contains "SCHEMA has Curator observation fields section" \
    "$SCHEMA_FILE" "^## Curator observation fields"
assert_contains "SCHEMA has Directional fields / typed-edge inverses section" \
    "$SCHEMA_FILE" "^## Directional fields and typed-edge inverses"

# --- Lint script installed ---
assert "wiki-lint-check.sh exists" "[ -f '$LINT' ]"
assert "wiki-lint-check.sh is executable" "[ -x '$LINT' ]"

# --- Helper to create a test page in the wiki ---
mkpage() {
    local name="$1"
    local content="$2"
    printf '%s' "$content" > "$WIKI_DIR/${name}.md"
}

# --- Canonical (default): full schema enforced ---

mkpage "Canonical-Valid" "---
type: concept
up: \"[[Home_${PROJECT_NAME}]]\"
---

A valid canonical page with non-empty body.
"
assert "canonical page with type+up+body passes lint" \
    "$LINT '$WIKI_DIR/Canonical-Valid.md'"

mkpage "Canonical-Missing-Type" "---
up: \"[[Home_${PROJECT_NAME}]]\"
---

A canonical page missing the type field.
"
assert "canonical page missing 'type:' fails lint" \
    "! $LINT '$WIKI_DIR/Canonical-Missing-Type.md' 2>/dev/null"

mkpage "Canonical-Empty-Body" "---
type: concept
up: \"[[Home_${PROJECT_NAME}]]\"
---
"
assert "canonical page with empty body fails lint" \
    "! $LINT '$WIKI_DIR/Canonical-Empty-Body.md' 2>/dev/null"

# --- Contribution: relaxed schema ---

mkpage "Topic--contrib-csweet1" "---
type: synthesis
status: contribution
contributor: claude-csweet1@${PROJECT_NAME}
contributed: 2026-05-30
target_topic: Topic
---

A contribution page. Does not need 'up:' or to be in the index.
"
assert "contribution with required fields passes (relaxed) lint" \
    "$LINT '$WIKI_DIR/Topic--contrib-csweet1.md'"

mkpage "Topic--contrib-missing-contributor" "---
type: synthesis
status: contribution
contributed: 2026-05-30
---

A contribution missing the contributor field.
"
assert "contribution missing 'contributor:' fails lint" \
    "! $LINT '$WIKI_DIR/Topic--contrib-missing-contributor.md' 2>/dev/null"

# --- Reconciled: frontmatter-only check ---

mkpage "Old-Contrib-Reconciled" "---
type: synthesis
status: reconciled
contributor: claude-csweet1@${PROJECT_NAME}
reconciled_into: Topic
reconciled_at: 2026-06-15
---
"
assert "reconciled page with required fields passes (body is frozen, not checked)" \
    "$LINT '$WIKI_DIR/Old-Contrib-Reconciled.md'"

# --- Curator + canonical: orthogonality ---

mkpage "Canonical-With-Curator-Pending" "---
type: concept
up: \"[[Home_${PROJECT_NAME}]]\"
curator_status: pending
curator_suggested_up: \"[[Different-MOC]]\"
curator_observations:
  - This might belong under a different MOC
---

A canonical page that the author flagged as uncertain about its placement.
"
assert "canonical + curator_status:pending passes (status and curator are orthogonal)" \
    "$LINT '$WIKI_DIR/Canonical-With-Curator-Pending.md'"

# --- Reconciled missing required field fails ---

mkpage "Reconciled-Missing-Into" "---
type: synthesis
status: reconciled
contributor: claude-csweet1@${PROJECT_NAME}
---
"
assert "reconciled page missing 'reconciled_into:' fails lint" \
    "! $LINT '$WIKI_DIR/Reconciled-Missing-Into.md' 2>/dev/null"

#!/usr/bin/env bash
# Stage 2: status-aware frontmatter + relaxed lint + KE-borrowed primitives.
# Applies to a sandbox derivative (created by init_derivative; SCHEMA stub
# present from Stage 0).
#
# Inputs:  SANDBOX env var pointing at the sandbox root.
# Effects:
#   1. Appends to wiki's SCHEMA: CoALA preamble, status lifecycle, curator
#      observation fields, directional fields and typed-edge inverses note.
#   2. Installs scripts/wiki-lint-check.sh: an executable structural lint
#      that implements the status-aware checks. (The MVP also updates the
#      wiki-lint skill Markdown for the LLM; here we focus on the
#      deterministic structural subset that can run in CI.)
#
# Idempotent: re-running does not duplicate sections.

set -euo pipefail

D="$SANDBOX/derivative"

# --- Find the wiki's SCHEMA file ---
WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
PROJECT_NAME=$(basename "$WIKI_DIR" .wiki)
SCHEMA_FILE="$WIKI_DIR/SCHEMA_${PROJECT_NAME}.md"

if [ ! -f "$SCHEMA_FILE" ]; then
    echo "  ERROR: Stage 0 baseline SCHEMA not found at $SCHEMA_FILE" >&2
    exit 1
fi

# --- Append new sections to SCHEMA (idempotent) ---
if ! grep -q "^## Cognitive architecture" "$SCHEMA_FILE"; then
    cat >> "$SCHEMA_FILE" <<'SCHEMA_APPEND_EOF'

## Cognitive architecture

This wiki is the **semantic memory layer** of a CoALA-grounded cognitive architecture (Sumers et al. 2023). Four memory types map to template components: working (CLAUDE.md + rules), procedural (skills + hooks), episodic (log_<project>.md + auto-memory), semantic (this wiki). Descriptive not prescriptive.

## Page status lifecycle

| Status | Authored by | Verifier rules |
|---|---|---|
| `canonical` (default) | Native agents | Full schema |
| `contribution` | Non-native agents | Relaxed (frontmatter parses, body valid) |
| `reconciled` | Frozen historical record | Frontmatter only |
| `declined` | Frozen historical record | Frontmatter only |
| `superseded` | Frozen historical record | Frontmatter only |

Status transitions are forward-only. If `status:` is absent, default is `canonical`.

## Curator observation fields (optional)

Orthogonal to `status:`. For contributors flagging ontology-fit uncertainty.

| Field | Values | Purpose |
|---|---|---|
| `curator_status:` | pending, reviewed, accepted, declined | Processing state |
| `curator_suggested_type:` | Any canonical type | Suggests better type |
| `curator_suggested_up:` | Wikilink | Suggests better parent |
| `curator_observations:` | List of strings | Free-text reasoning |

Never required. Reconciler reads `curator_status: pending` as a stronger review signal.

## Directional fields and typed-edge inverses

The contribution lifecycle introduces directional fields (`target_topic:`, `reconciled_into:`, `contributor:`, `superseded_by:`, `influenced_by:`, `renamed_from:`). Some have implicit aggregated inverses (`reconciled_into:` <-> `sources:`; `contributor:` <-> `contributors:`); others do not. This mirrors a pre-existing asymmetry in the template's typed edges (`supports:`, `extends:`, `criticizes:`) flagged in template issue #3. The MVP does not resolve #3; it commits to follow whatever convention the template adopts.
SCHEMA_APPEND_EOF

    # Commit the SCHEMA update inside the wiki repo. Without this commit
    # the SCHEMA file would remain as unstaged modifications, which later
    # stages' git operations (especially Stage 4's rebase) refuse to run
    # over.
    (
        cd "$(dirname "$SCHEMA_FILE")"
        git add "$(basename "$SCHEMA_FILE")"
        git commit -q -m "Schema: CoALA, status lifecycle, curator fields, directional-inverses note"
    )
fi

# --- Install wiki-lint-check.sh ---
mkdir -p "$D/scripts"
cat > "$D/scripts/wiki-lint-check.sh" <<'LINT_EOF'
#!/usr/bin/env bash
# wiki-lint-check.sh: status-aware structural lint for one wiki page.
# Usage: wiki-lint-check.sh <file.md>
# Exit:  0 if valid, 1 if violations found, 2 for usage errors.

set -uo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $(basename "$0") <file.md>" >&2
    exit 2
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
    echo "File not found: $FILE" >&2
    exit 2
fi

# Extract frontmatter (between first --- and second ---)
FM=$(awk '
    /^---[[:space:]]*$/ { count++; if (count == 2) exit; next }
    count == 1 { print }
' "$FILE")

if [ -z "$FM" ]; then
    echo "VIOLATION: $FILE has no frontmatter" >&2
    exit 1
fi

# Extract body (everything after second ---)
BODY=$(awk '
    /^---[[:space:]]*$/ { count++; next }
    count >= 2 { print }
' "$FILE")

# Helpers
get_field() {
    echo "$FM" | grep -E "^${1}:[[:space:]]" | head -1 \
        | sed -E "s/^${1}:[[:space:]]*//" \
        | sed -E 's/^"(.*)"$/\1/' \
        | sed -E "s/^'(.*)'$/\1/"
}

has_field() {
    echo "$FM" | grep -qE "^${1}:[[:space:]]"
}

VIOLATIONS=0
violate() {
    echo "VIOLATION: $FILE: $1" >&2
    VIOLATIONS=$((VIOLATIONS+1))
}

STATUS=$(get_field "status")
[ -z "$STATUS" ] && STATUS="canonical"

BODY_NONEMPTY=$(echo "$BODY" | grep -v '^[[:space:]]*$' | head -1)

case "$STATUS" in
    canonical)
        has_field "type" || violate "canonical page missing 'type:'"
        has_field "up" || violate "canonical page missing 'up:'"
        TYPE=$(get_field "type")
        [ "$TYPE" = "untyped" ] && violate "canonical page has 'type: untyped'"
        [ -z "$BODY_NONEMPTY" ] && violate "canonical page has empty body"
        ;;
    contribution)
        has_field "type" || violate "contribution missing 'type:'"
        has_field "contributor" || violate "contribution missing 'contributor:'"
        has_field "contributed" || violate "contribution missing 'contributed:'"
        [ -z "$BODY_NONEMPTY" ] && violate "contribution has empty body"
        ;;
    reconciled)
        has_field "contributor" || violate "reconciled page missing 'contributor:'"
        has_field "reconciled_into" || violate "reconciled page missing 'reconciled_into:'"
        ;;
    declined)
        has_field "contributor" || violate "declined page missing 'contributor:'"
        has_field "declined_at" || violate "declined page missing 'declined_at:'"
        ;;
    superseded)
        has_field "contributor" || violate "superseded page missing 'contributor:'"
        has_field "superseded_by" || violate "superseded page missing 'superseded_by:'"
        ;;
    *)
        violate "unknown status: $STATUS"
        ;;
esac

[ "$VIOLATIONS" -gt 0 ] && exit 1
exit 0
LINT_EOF
chmod +x "$D/scripts/wiki-lint-check.sh"

echo "  Stage 2 patch applied: SCHEMA enriched, wiki-lint-check.sh installed."

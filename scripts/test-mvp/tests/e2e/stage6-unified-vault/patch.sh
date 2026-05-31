#!/usr/bin/env bash
# Stage 6: unified-vault protection.
# Depends on Stage 2 (appends to SCHEMA Stage 2 enriched; extends the
# wiki-lint-check.sh that Stage 2 installs).
#
# Inputs:  SANDBOX env var pointing at the sandbox root.
# Effects:
#   1. Appends a "Namespacing for unified personal vaults" section to the
#      wiki's SCHEMA (idempotent), and commits it.
#   2. Rewrites scripts/wiki-lint-check.sh to add a nav-page namespacing
#      check on top of the Stage 2 status-aware checks.
#
# Idempotent.

set -euo pipefail

D="$SANDBOX/derivative"

WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
PROJECT_NAME=$(basename "$WIKI_DIR" .wiki)
SCHEMA_FILE="$WIKI_DIR/SCHEMA_${PROJECT_NAME}.md"

if [ ! -f "$SCHEMA_FILE" ]; then
    echo "  ERROR: SCHEMA not found at $SCHEMA_FILE (Stage 2 must run first)" >&2
    exit 1
fi

# --- Append namespacing mandate to SCHEMA (idempotent) ---
if ! grep -q "^## Namespacing for unified personal vaults" "$SCHEMA_FILE"; then
    cat >> "$SCHEMA_FILE" <<'NS_EOF'

## Namespacing for unified personal vaults [MANDATORY]

Project-shared nav artifacts MUST carry the project suffix so multiple project wikis can compose into one unified Obsidian vault without collision:

| Nav artifact | Required form |
|---|---|
| Home page | `Home_<project>.md` |
| Index | `index_<project>.md` |
| Activity log | `log_<project>.md` |
| Schema reference | `SCHEMA_<project>.md` |

A `Home.md` bridge file (no namespace) is allowed at the wiki root only as a redirect to `Home_<project>.md`. Flag `Home.md` if it has substantive content.

If your project adopts MOCs (optional, agentic-vault pattern), follow the same namespacing convention: `<topic>-MOC_<project>.md`. Not enforced by the base lint.
NS_EOF

    # Commit the SCHEMA update (Stage 2 set the precedent)
    (
        cd "$(dirname "$SCHEMA_FILE")"
        git add "$(basename "$SCHEMA_FILE")"
        git commit -q -m "Schema: namespacing mandate for unified-vault composition"
    )
fi

# --- Rewrite wiki-lint-check.sh with Stage 2 + Stage 6 checks ---
LINT="$D/scripts/wiki-lint-check.sh"
mkdir -p "$D/scripts"
cat > "$LINT" <<'LINT_EOF'
#!/usr/bin/env bash
# wiki-lint-check.sh: status-aware structural lint for one wiki page,
# plus nav-page namespacing check.
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

# ----- Status-aware checks (Stage 2) -------------------------------------
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

# ----- Nav-page namespacing check (Stage 6) ------------------------------
# Nav artifacts (Home/index/log/SCHEMA) must carry the project suffix or
# they collide when multiple project wikis are cloned into a single
# Obsidian vault. Home.md is an exception: allowed only as a tiny redirect
# bridge to Home_<project>.md, flagged if it has substantive content.
BASENAME=$(basename "$FILE")
BODY_CHARS=$(printf '%s' "$BODY" | wc -c | tr -d ' ')

case "$BASENAME" in
    Home.md)
        # Allowed as redirect bridge only; flag if body has substantive content
        if [ "$BODY_CHARS" -gt 300 ]; then
            violate "Home.md has substantive content (~${BODY_CHARS} chars); should be a tiny redirect bridge to Home_<project>.md"
        fi
        ;;
    index.md|log.md|SCHEMA.md)
        STEM=$(basename "$BASENAME" .md)
        violate "$BASENAME is not project-suffixed (collides in unified vault); rename to ${STEM}_<project>.md"
        ;;
esac

[ "$VIOLATIONS" -gt 0 ] && exit 1
exit 0
LINT_EOF
chmod +x "$LINT"

echo "  Stage 6 patch applied: SCHEMA namespacing mandate appended, wiki-lint-check.sh extended with nav-page check."

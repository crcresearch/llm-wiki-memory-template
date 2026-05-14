#!/usr/bin/env bash
#
# init-wiki.sh — Bootstrap or update an LLM-maintained wiki for any project.
#
# Usage:
#   ./init-wiki.sh                        # Auto-detects repo name, uses wiki/ directory
#   ./init-wiki.sh --name "My Project"    # Custom project name
#   ./init-wiki.sh --github               # Clone the GitHub wiki repo instead of creating locally
#
# Modes:
#   Create — wiki doesn't exist yet. Creates all files from scratch with
#            namespaced navigation files for Obsidian compatibility.
#   Update — wiki exists. Adds missing sections to SCHEMA and CLAUDE.md
#            without overwriting existing content.
#
# Navigation files are namespaced to avoid collisions when multiple wikis
# share an Obsidian vault:
#   Home_${REPO_NAME}.md, index_${REPO_NAME}.md, log_${REPO_NAME}.md,
#   SCHEMA_${REPO_NAME}.md
#
# Home.md is kept as a redirect for GitHub wiki compatibility.
#
# ─── FOR THE LLM ──────────────────────────────────────────────────────────────
# If a user gave you the path to this script, EXECUTE it — do NOT reimplement
# it manually. It is idempotent: safe to re-run on existing wikis (auto-detects
# create vs. update mode).
#
# Before running, if llm-wiki.md exists at the repo root, read it for context
# on the underlying pattern (compounding wiki vs. RAG; LLM owns the wiki layer;
# Obsidian + LLM workflow). This shapes judgment calls during the first ingest.
#
# After it completes successfully, perform the first ingest:
#   1. Read the project README and any key docs the user points you to.
#   2. Create initial concept/entity pages per wiki/<repo>.wiki/SCHEMA_<repo>.md.
#   3. Add the new pages to index_<repo>.md and append a log_<repo>.md entry.
#
# Flags:
#   --name "Display Name"   custom project name (default: repo name)
#   --github                clone an existing GitHub wiki instead of init'ing locally
# ──────────────────────────────────────────────────────────────────────────────
#

set -euo pipefail

# --- Parse arguments ---
PROJECT_NAME=""
USE_GITHUB=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --name) PROJECT_NAME="$2"; shift 2 ;;
        --github) USE_GITHUB=true; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Detect project info ---
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REPO_NAME=$(basename "$REPO_ROOT")

if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME="$REPO_NAME"
fi

WIKI_DIR="$REPO_ROOT/wiki/${REPO_NAME}.wiki"

# Namespaced file names
HOME_NS="Home_${REPO_NAME}"
INDEX_NS="index_${REPO_NAME}"
LOG_NS="log_${REPO_NAME}"
SCHEMA_NS="SCHEMA_${REPO_NAME}"

# --- Detect mode ---
if [[ -f "$WIKI_DIR/${SCHEMA_NS}.md" ]] || [[ -f "$WIKI_DIR/SCHEMA.md" ]]; then
    MODE="update"
    echo "Existing wiki detected at $WIKI_DIR — running in update mode."
else
    MODE="create"
    echo "No wiki found — creating new wiki at $WIKI_DIR."
fi

# --- Helper: append a section to a file if a marker string is absent ---
append_section_if_missing() {
    local file="$1"
    local marker="$2"
    local content="$3"
    if [[ -f "$file" ]] && grep -qF "$marker" "$file"; then
        return 1  # already present
    fi
    printf '\n%s\n' "$content" >> "$file"
    return 0  # added
}

# --- Create or clone wiki (create mode only) ---
if [[ "$MODE" == "create" ]]; then
    if $USE_GITHUB; then
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
        if [[ -z "$REMOTE_URL" ]]; then
            echo "Error: No git remote 'origin' found. Can't derive GitHub wiki URL."
            exit 1
        fi
        WIKI_URL=$(echo "$REMOTE_URL" | sed 's/\.git$/.wiki.git/')
        echo "Cloning GitHub wiki from $WIKI_URL ..."
        mkdir -p "$REPO_ROOT/wiki"
        git clone "$WIKI_URL" "$WIKI_DIR" 2>/dev/null || {
            echo "Could not clone wiki. You may need to create the wiki on GitHub first"
            echo "(go to the repo → Wiki tab → create a page → save)."
            echo "Falling back to local initialization..."
            USE_GITHUB=false
        }
    fi

    if ! $USE_GITHUB; then
        mkdir -p "$WIKI_DIR"
        if [[ ! -d "$WIKI_DIR/.git" ]]; then
            git -C "$WIKI_DIR" init
            echo "Initialized local wiki repo at $WIKI_DIR"
        fi
    fi
fi

# --- Write Home_${REPO_NAME}.md (create only — never overwrite) ---
if [[ ! -f "$WIKI_DIR/${HOME_NS}.md" ]]; then
cat > "$WIKI_DIR/${HOME_NS}.md" << HOMEEOF
---
type: index
up: "[[WIKI-INDEX]]"
---

# ${PROJECT_NAME}

Welcome to the project wiki. This is an LLM-maintained knowledge base that grows as the project evolves.

## Navigation

- **[Index](${INDEX_NS})** — Full catalog of all wiki pages
- **[Log](${LOG_NS})** — Chronological record of wiki updates

## Getting Started

Ask your LLM to ingest key project documents:

> "Read the README and any key docs, then build out the wiki with concept pages, entity pages, and cross-references."

See [SCHEMA](${SCHEMA_NS}) for wiki conventions and maintenance workflows.
HOMEEOF
fi

# --- Write Home.md redirect (GitHub wiki landing page) ---
if [[ ! -f "$WIKI_DIR/Home.md" ]] || ! grep -qF "redirect" "$WIKI_DIR/Home.md" 2>/dev/null; then
cat > "$WIKI_DIR/Home.md" << REDIRECTEOF
<!-- redirect: this file exists for GitHub wiki compatibility -->
<!-- The real home page is ${HOME_NS}.md -->
See [${PROJECT_NAME}](${HOME_NS})
REDIRECTEOF
fi

# --- Write index_${REPO_NAME}.md (create only — never overwrite) ---
if [[ ! -f "$WIKI_DIR/${INDEX_NS}.md" ]]; then
cat > "$WIKI_DIR/${INDEX_NS}.md" << INDEXEOF
---
type: index
up: "[[${HOME_NS}]]"
---

# Index — ${PROJECT_NAME}

Catalog of all wiki pages, organized by category.

## Overview
- [Home](${HOME_NS}) — Project summary and navigation

<!-- Add pages here as the wiki grows -->
INDEXEOF
fi

# --- Write log_${REPO_NAME}.md (create only — never overwrite) ---
if [[ ! -f "$WIKI_DIR/${LOG_NS}.md" ]]; then
cat > "$WIKI_DIR/${LOG_NS}.md" << LOGEOF
---
type: index
up: "[[${HOME_NS}]]"
---

# Log — ${PROJECT_NAME}

Chronological record of wiki activity.

## [$(date +%Y-%m-%d)] create | Wiki initialized
- Created wiki structure with namespaced navigation files
- Ready for first ingest
LOGEOF
fi

# --- SCHEMA: create or update ---
if [[ "$MODE" == "create" ]]; then
    cat > "$WIKI_DIR/${SCHEMA_NS}.md" << SCHEMAEOF
---
type: reference
up: "[[${HOME_NS}]]"
---

# Wiki Schema — ${PROJECT_NAME}

> Conventions and workflows for LLM maintenance of this wiki.
> Based on the [llm-wiki pattern](https://github.com/tobi/llm-wiki).

## Purpose

This wiki is a persistent, compounding knowledge base. The LLM writes and maintains all pages. The human curates sources, directs analysis, and asks questions. Knowledge is compiled once and kept current, not re-derived every session.

## Source of Truth

**Raw sources** (immutable — read but never modify):
- Project code and documentation
- Data files and results
- External references

**The wiki** (LLM-owned — create, update, cross-reference, maintain):
- All \`.md\` files in this directory

## Page Format

Every content page should include:

1. **Title** — \`# Page Name\` as H1
2. **Opening line** — One sentence summarizing what this page is about
3. **Body** — Tables, prose, code blocks as appropriate. Concise reference style.
4. **Cross-references** — \`See also:\` line at the bottom with \`[Display Name](Page-Name)\` links

## Frontmatter

Every page gets standard YAML frontmatter:

\`\`\`markdown
---
type: concept | entity | source-summary | synthesis | index | comparison | untyped
up: "[[Parent-Page]]"
tags: [topic-a, topic-b]
---
\`\`\`

**Required fields**:
- \`type:\` — what kind of page this is (use \`untyped\` if unsure)
- \`up:\` — parent page in the hierarchy (usually a category page or index)

**Optional typed edges** (add when the relationship is clear):
- \`source:\` — literature or raw source this page summarizes
- \`extends:\` — concept or page this builds upon
- \`supports:\` / \`criticizes:\` — claim or page this provides evidence for or against
- \`related:\` — lateral connection (prefer specific edges above when possible)

**Rules**:
- Every page gets frontmatter — no exceptions
- Use \`type: untyped\` rather than skipping frontmatter entirely
- Cross-references in frontmatter use \`[[Page-Name]]\` wikilink format for Obsidian compatibility
- Cross-references in body text use \`[Display](Page-Name)\` format for GitHub wiki compatibility
- The frontmatter feeds the knowledge graph pipeline for SPARQL queries

## Naming Convention

- Use \`Title-Case-Hyphenated.md\` for page files (e.g., \`Neural-Embeddings.md\`)
- Navigation files are namespaced: \`index_${REPO_NAME}.md\`, \`log_${REPO_NAME}.md\`, etc.

## Special Files

### ${INDEX_NS}.md
- Catalog of every page with one-line descriptions
- Organized by category
- **Update on every ingest**

### ${LOG_NS}.md
- Append-only chronological record
- Format: \`## [YYYY-MM-DD] verb | Subject\` (verbs: ingest, query, lint, update, create)
- 2-5 bullet points per entry
- **Append on every operation**

### Home.md
- GitHub wiki redirect only — do not edit
- Real home page is [${HOME_NS}](${HOME_NS})

## Cross-Referencing

- Use \`[Display Text](Page-Name)\` format in body text (GitHub wiki style)
- Use \`[[Page-Name]]\` wikilinks in frontmatter edge fields (Obsidian graph)
- Every page should have at least 2 inbound and 2 outbound links
- Link concepts on first mention within a page
- Bidirectional: if A links to B, B should link back to A

## Operations

### Ingest (new work completed)

When new sources, experiments, or milestones arrive:

1. Read the source material
2. Discuss key takeaways with the user
3. Create new pages or update existing ones (with frontmatter)
4. Update cross-references on all affected pages
5. Update \`${INDEX_NS}.md\`
6. Append to \`${LOG_NS}.md\`

A single ingest typically touches 5-15 pages.

### Query (answering questions)

1. Read \`${INDEX_NS}.md\` to find relevant pages
2. Read those pages and synthesize an answer
3. If the answer is valuable and reusable, offer to file it as a new page

### Lint (health check)

Periodically check for:
- Orphan pages (no inbound links)
- Dead links (links to non-existent pages)
- Stale claims (superseded by newer work)
- Missing pages (concepts mentioned but lacking their own page)
- Missing cross-references
- **Pages missing frontmatter** — add it based on page content (infer type, parent, tags)
- **Pages with \`type: untyped\`** — review and assign a proper type if now obvious

## When to Update

- **Always**: After completing significant work (experiments, milestones, key findings)
- **Always**: When findings contradict or supersede previous ones
- **Often**: When analytical questions produce reusable answers
- **Periodically**: Lint pass every few sessions

## When NOT to Update

- Routine debugging or code fixes (git history is enough)
- Temporary analysis that won't be referenced again
- Speculative plans that haven't been executed

## Git Workflow

After wiki updates:
1. Stage changed files by name
2. Commit with descriptive message
3. Do NOT push unless the user requests it

## Evolution

Update this schema as the project's needs change. It's a living document.
SCHEMAEOF

else
    # Update mode — add missing sections to existing SCHEMA
    # Find the schema file (namespaced or bare)
    if [[ -f "$WIKI_DIR/${SCHEMA_NS}.md" ]]; then
        SCHEMA_FILE="$WIKI_DIR/${SCHEMA_NS}.md"
    else
        SCHEMA_FILE="$WIKI_DIR/SCHEMA.md"
    fi

    UPDATED_SECTIONS=()

    # Add Frontmatter section if missing
    if append_section_if_missing "$SCHEMA_FILE" "## Frontmatter" "## Frontmatter

Every page gets standard YAML frontmatter:

\`\`\`markdown
---
type: concept | entity | source-summary | synthesis | index | comparison | untyped
up: \"[[Parent-Page]]\"
tags: [topic-a, topic-b]
---
\`\`\`

**Required fields**:
- \`type:\` — what kind of page this is (use \`untyped\` if unsure)
- \`up:\` — parent page in the hierarchy (usually a category page or index)

**Optional typed edges** (add when the relationship is clear):
- \`source:\` — literature or raw source this page summarizes
- \`extends:\` — concept or page this builds upon
- \`supports:\` / \`criticizes:\` — claim or page this provides evidence for or against
- \`related:\` — lateral connection (prefer specific edges above when possible)

**Rules**:
- Every page gets frontmatter — no exceptions
- Use \`type: untyped\` rather than skipping frontmatter entirely
- Cross-references in frontmatter use \`[[Page-Name]]\` wikilink format for Obsidian compatibility
- Cross-references in body text use \`[Display](Page-Name)\` format for GitHub wiki compatibility
- The frontmatter feeds the knowledge graph pipeline for SPARQL queries"; then
        UPDATED_SECTIONS+=("Frontmatter")
    fi

    # Add frontmatter lint rules if missing
    if append_section_if_missing "$SCHEMA_FILE" "Pages missing frontmatter" '### Lint: Frontmatter checks

Also check during lint:
- **Pages missing frontmatter** — add it based on page content (infer type, parent, tags)
- **Pages with `type: untyped`** — review and assign a proper type if now obvious'; then
        UPDATED_SECTIONS+=("Frontmatter lint rules")
    fi

    # Replace old "No YAML frontmatter" instruction if present
    if grep -qF "No YAML frontmatter" "$SCHEMA_FILE"; then
        sed -i '' 's/No YAML frontmatter\. No tags\. Simple markdown that renders on GitHub wikis\./See the Frontmatter section below for frontmatter conventions./' "$SCHEMA_FILE" 2>/dev/null || \
        sed -i 's/No YAML frontmatter\. No tags\. Simple markdown that renders on GitHub wikis\./See the Frontmatter section below for frontmatter conventions./' "$SCHEMA_FILE"
        UPDATED_SECTIONS+=("Replaced 'No YAML frontmatter' directive")
    fi

    # Replace old HTML-comment frontmatter instruction if present
    if grep -qF "HTML comment" "$SCHEMA_FILE"; then
        sed -i '' 's/wrapped in an HTML comment so it renders cleanly on GitHub wikis/standard YAML frontmatter/' "$SCHEMA_FILE" 2>/dev/null || \
        sed -i 's/wrapped in an HTML comment so it renders cleanly on GitHub wikis/standard YAML frontmatter/' "$SCHEMA_FILE"
        UPDATED_SECTIONS+=("Switched from HTML-comment to standard frontmatter")
    fi

    if [[ ${#UPDATED_SECTIONS[@]} -gt 0 ]]; then
        echo "Updated SCHEMA:"
        for s in "${UPDATED_SECTIONS[@]}"; do
            echo "  + $s"
        done
    else
        echo "SCHEMA already up to date."
    fi
fi

# --- WIKI-INDEX: recursive registration ---
# Walk up from the wiki directory, creating/updating WIKI-INDEX files
register_in_wiki_index() {
    local wiki_dir="$1"
    local wiki_name="$2"
    local home_page="$3"
    local description="$4"

    local parent_dir
    parent_dir="$(dirname "$wiki_dir")"
    local parent_name
    parent_name="$(basename "$parent_dir")"

    # Determine the index filename for this level
    # Top-level "wiki/" gets bare WIKI-INDEX.md
    # Sub-collections get WIKI-INDEX_${collection_name}.md
    local index_file
    if [[ "$parent_name" == "wiki" ]]; then
        index_file="$parent_dir/WIKI-INDEX.md"
    else
        index_file="$parent_dir/WIKI-INDEX_${parent_name}.md"
    fi

    # Create the index file if it doesn't exist
    if [[ ! -f "$index_file" ]]; then
        local index_basename
        index_basename="$(basename "$index_file" .md)"
        cat > "$index_file" << WIKIIDXEOF
---
type: index
---

# Wiki Index — ${parent_name}

## Wikis
- [[${home_page}]] — ${description}
WIKIIDXEOF
        echo "Created $index_file"
    else
        # Add entry if not already present
        if ! grep -qF "[[${home_page}]]" "$index_file"; then
            # Find the Wikis section and append, or just append
            if grep -qF "## Wikis" "$index_file"; then
                # Append after the Wikis heading (find line number, insert after)
                local line_num
                line_num=$(grep -n "## Wikis" "$index_file" | tail -1 | cut -d: -f1)
                sed -i '' "${line_num}a\\
- [[${home_page}]] — ${description}" "$index_file" 2>/dev/null || \
                sed -i "${line_num}a\\
- [[${home_page}]] — ${description}" "$index_file"
            else
                printf '\n## Wikis\n- [[%s]] — %s\n' "${home_page}" "${description}" >> "$index_file"
            fi
            echo "Registered ${wiki_name} in $(basename "$index_file")"
        else
            echo "$(basename "$index_file") already has entry for ${wiki_name}"
        fi
    fi

    # Recurse up: register this collection's index in the grandparent
    local grandparent_dir
    grandparent_dir="$(dirname "$parent_dir")"
    local grandparent_name
    grandparent_name="$(basename "$grandparent_dir")"
    local index_basename
    index_basename="$(basename "$index_file" .md)"

    # Stop recursion at repo root or if we've left the wiki/ tree
    if [[ "$grandparent_dir" == "$REPO_ROOT" ]] || [[ "$grandparent_dir" == "/" ]]; then
        return
    fi

    # Check if grandparent has a WIKI-INDEX to register in
    local grandparent_index
    if [[ "$grandparent_name" == "wiki" ]]; then
        grandparent_index="$grandparent_dir/WIKI-INDEX.md"
    else
        grandparent_index="$grandparent_dir/WIKI-INDEX_${grandparent_name}.md"
    fi

    if [[ -f "$grandparent_index" ]] || [[ "$grandparent_name" == "wiki" ]]; then
        # Register this collection in the grandparent
        if [[ ! -f "$grandparent_index" ]]; then
            cat > "$grandparent_index" << GPIDXEOF
---
type: index
---

# Wiki Index

## Collections
- [[${index_basename}]] — ${parent_name} wikis
GPIDXEOF
            echo "Created $grandparent_index"
        elif ! grep -qF "[[${index_basename}]]" "$grandparent_index"; then
            if grep -qF "## Collections" "$grandparent_index"; then
                local gp_line
                gp_line=$(grep -n "## Collections" "$grandparent_index" | tail -1 | cut -d: -f1)
                sed -i '' "${gp_line}a\\
- [[${index_basename}]] — ${parent_name} wikis" "$grandparent_index" 2>/dev/null || \
                sed -i "${gp_line}a\\
- [[${index_basename}]] — ${parent_name} wikis" "$grandparent_index"
            else
                printf '\n## Collections\n- [[%s]] — %s wikis\n' "${index_basename}" "${parent_name}" >> "$grandparent_index"
            fi
            echo "Registered ${parent_name} collection in $(basename "$grandparent_index")"
        fi
    fi
}

# Register this wiki in the WIKI-INDEX hierarchy
register_in_wiki_index "$WIKI_DIR" "$REPO_NAME" "$HOME_NS" "$PROJECT_NAME wiki"

# --- CLAUDE.md: create or update ---
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
CLAUDE_UPDATED=()

WIKI_SECTION="## Wiki

This project maintains a **persistent wiki** at \`wiki/${REPO_NAME}.wiki/\` (separate git repo) following the [llm-wiki pattern](https://github.com/tobi/llm-wiki). The wiki is an LLM-maintained, interlinked knowledge base that compounds over time.

**Read \`wiki/${REPO_NAME}.wiki/${SCHEMA_NS}.md\` before making wiki changes.** It defines page formats, frontmatter conventions, cross-referencing, and the three operations:

- **Ingest**: After completing significant work, update the wiki (create/update pages, cross-references, \`${INDEX_NS}.md\`, \`${LOG_NS}.md\`).
- **Query**: When answering analytical questions, search the wiki first (\`${INDEX_NS}.md\` → relevant pages). File valuable answers as new pages.
- **Lint**: Periodically health-check for orphan pages, stale claims, missing cross-references, and missing frontmatter."

KG_SUBSECTION="### Knowledge Graph

The wiki's frontmatter feeds a knowledge graph pipeline (\`scripts/kg/\`) that enables SPARQL queries over wiki content. The pipeline extracts frontmatter and body cross-references, converts them to RDF triples, and loads them into a Fuseki endpoint.

- **Rebuild**: \`./scripts/kg/build-graph.sh\` after wiki updates
- **Query**: SPARQL endpoint at \`http://localhost:3030/wiki/sparql\` (when Fuseki is running)
- Typed edges in frontmatter (\`extends:\`, \`supports:\`, \`criticizes:\`) produce rich graph relationships
- Body cross-references (\`[text](Page-Name)\`) produce \`mentions\` edges
- Pages without frontmatter are included as \`untyped\` nodes — no data is lost"

if [[ -f "$CLAUDE_MD" ]]; then
    if ! grep -qF "## Wiki" "$CLAUDE_MD"; then
        printf '\n---\n\n%s\n' "$WIKI_SECTION" >> "$CLAUDE_MD"
        CLAUDE_UPDATED+=("Wiki section")
    else
        # Wiki section exists — check for missing content within it

        if grep -qF "missing cross-references." "$CLAUDE_MD" && ! grep -qF "missing frontmatter" "$CLAUDE_MD"; then
            sed -i '' 's/missing cross-references\./missing cross-references, and missing frontmatter./' "$CLAUDE_MD" 2>/dev/null || \
            sed -i 's/missing cross-references\./missing cross-references, and missing frontmatter./' "$CLAUDE_MD"
            CLAUDE_UPDATED+=("Updated Lint line to include frontmatter checks")
        fi

        if ! grep -qF "${SCHEMA_NS}.md" "$CLAUDE_MD"; then
            SCHEMA_LINE="**Read \`wiki/${REPO_NAME}.wiki/${SCHEMA_NS}.md\` before making wiki changes.** It defines page formats, frontmatter conventions, cross-referencing, and the three operations (Ingest, Query, Lint)."
            if append_section_if_missing "$CLAUDE_MD" "${SCHEMA_NS}.md" "$SCHEMA_LINE"; then
                CLAUDE_UPDATED+=("Namespaced SCHEMA reference")
            fi
        fi
    fi

    if ! grep -qF "### Knowledge Graph" "$CLAUDE_MD"; then
        printf '\n%s\n' "$KG_SUBSECTION" >> "$CLAUDE_MD"
        CLAUDE_UPDATED+=("Knowledge Graph subsection")
    fi
else
    cat > "$CLAUDE_MD" << CLAUDEEOF
# CLAUDE.md

> Context file for AI assistants working on this project.

$WIKI_SECTION

$KG_SUBSECTION
CLAUDEEOF
    CLAUDE_UPDATED+=("Created CLAUDE.md with Wiki + Knowledge Graph sections")
fi

if [[ ${#CLAUDE_UPDATED[@]} -gt 0 ]]; then
    echo "Updated CLAUDE.md:"
    for s in "${CLAUDE_UPDATED[@]}"; do
        echo "  + $s"
    done
else
    echo "CLAUDE.md already up to date."
fi

# --- Commit changes in wiki repo ---
cd "$WIKI_DIR"
git add -A
if git diff --cached --quiet 2>/dev/null; then
    echo ""
    echo "No wiki changes to commit."
else
    if [[ "$MODE" == "create" ]]; then
        git commit -m "Initialize wiki with llm-wiki pattern (namespaced)" --quiet 2>/dev/null || true
    else
        git commit -m "Update wiki schema: frontmatter + KG support" --quiet 2>/dev/null || true
    fi
fi

# --- Log entry (update mode only) ---
if [[ "$MODE" == "update" ]]; then
    # Find the log file (namespaced or bare)
    if [[ -f "$WIKI_DIR/${LOG_NS}.md" ]]; then
        LOG_FILE="$WIKI_DIR/${LOG_NS}.md"
    elif [[ -f "$WIKI_DIR/log.md" ]]; then
        LOG_FILE="$WIKI_DIR/log.md"
    else
        LOG_FILE=""
    fi

    if [[ -n "$LOG_FILE" ]] && ! grep -qF "frontmatter convention" "$LOG_FILE"; then
        cat >> "$LOG_FILE" << EOF

## [$(date +%Y-%m-%d)] update | Added frontmatter convention
- Schema updated with standard YAML frontmatter format
- Lint rules now check for missing frontmatter
- Knowledge graph pipeline support added
EOF
        cd "$WIKI_DIR"
        git add "$(basename "$LOG_FILE")"
        git commit -m "Log: frontmatter convention update" --quiet 2>/dev/null || true
    fi
fi

# --- Summary ---
echo ""
if [[ "$MODE" == "create" ]]; then
    echo "✓ Wiki initialized at $WIKI_DIR"
    echo ""
    echo "Navigation files:"
    echo "  Home:   ${HOME_NS}.md (redirect: Home.md)"
    echo "  Index:  ${INDEX_NS}.md"
    echo "  Log:    ${LOG_NS}.md"
    echo "  Schema: ${SCHEMA_NS}.md"
    echo ""
    echo "Next steps:"
    echo "  1. Start a conversation with your LLM in this repo"
    echo "  2. Ask it to ingest your key documents into the wiki"
    echo "  3. The wiki will grow from there"
else
    echo "✓ Wiki updated at $WIKI_DIR"
    echo ""
    echo "Next steps:"
    echo "  1. Run a lint pass to add frontmatter to existing pages:"
    echo "     Tell your LLM: \"Lint the wiki — focus on adding frontmatter to pages that are missing it\""
    echo "  2. After frontmatter is in place, build the knowledge graph:"
    echo "     ./scripts/kg/build-graph.sh"
fi
echo ""
echo "If using GitHub wiki, push with:"
echo "  cd $WIKI_DIR && git push origin master"

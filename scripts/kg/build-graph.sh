#!/usr/bin/env bash
# scripts/kg/build-graph.sh
#
# Build the knowledge graph from a wiki's frontmatter (and body links).
# Single entry point as documented in the template wiki page
# Knowledge-Graph-Pipeline.
#
# Pipeline:
#   1. Fetch spec from https://la3d.github.io/llm-wiki-colab/ into
#      scripts/kg/.cache/ (ontology.ttl, shapes.ttl, context.jsonld).
#   2. Extract wiki/*.md frontmatter + body links to JSON-LD via
#      scripts/kg/wiki-to-jsonld.py.
#   3. JSON-LD -> Turtle via riot.
#   4. Materialise inverse edges, area inheritance, hub flag via arq
#      CONSTRUCT queries.
#   5. SHACL validate against the fetched shapes.ttl.
#
# Outputs (scripts/kg/build/):
#   graph.jsonld           raw extraction (JSON-LD)
#   graph.ttl              base Turtle
#   graph-weights.ttl      RDF-star weighted mentions
#   graph-full.ttl         base + materialised triples
#   validation-report.ttl  SHACL conformance report
#
# Usage:
#   ./scripts/kg/build-graph.sh                       (default wiki)
#   ./scripts/kg/build-graph.sh --wiki=PATH           (custom wiki)
#   ./scripts/kg/build-graph.sh --stats               (extractor stats)
#   ./scripts/kg/build-graph.sh --refresh-spec        (re-fetch cached spec)
#   ./scripts/kg/build-graph.sh --skip-materialize    (no inverses)
#   ./scripts/kg/build-graph.sh --skip-validate       (no SHACL pass)
#
# The published spec is the source of truth: it lives at
# https://la3d.github.io/llm-wiki-colab/, the IRIs in the graph point
# there, and refreshing the cache picks up upstream changes. The cache
# is gitignored.
#
# This script and scripts/kg/wiki-to-jsonld.py are derived from prior
# work at https://github.com/LA3D/llm-wiki-colab (MIT). They live here
# locally so they can evolve with the template.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CACHE_DIR="$SCRIPT_DIR/.cache"
BUILD_DIR="$SCRIPT_DIR/build"

# --- Defaults (override via env vars or CLI) ---

SPEC_BASE_URL="${SPEC_BASE_URL:-https://la3d.github.io/llm-wiki-colab}"
SPEC_CACHE_DAYS="${SPEC_CACHE_DAYS:-7}"

# Default wiki: first wiki/*.wiki/ directory under repo root, if any
default_wiki() {
    if [[ -d "$REPO_ROOT/wiki" ]]; then
        for d in "$REPO_ROOT/wiki"/*.wiki; do
            if [[ -d "$d" ]]; then
                printf '%s' "$d"
                return
            fi
        done
    fi
    printf ''
}
WIKI_DIR="${WIKI_DIR:-$(default_wiki)}"

# --- CLI ---

STATS=""
REFRESH_SPEC=""
SKIP_MATERIALIZE=""
SKIP_VALIDATE=""

for arg in "$@"; do
    case "$arg" in
        --wiki=*)           WIKI_DIR="${arg#--wiki=}" ;;
        --stats)            STATS="--stats" ;;
        --refresh-spec)     REFRESH_SPEC=1 ;;
        --skip-materialize) SKIP_MATERIALIZE=1 ;;
        --skip-validate)    SKIP_VALIDATE=1 ;;
        --help|-h)
            grep '^#' "$0" | sed -e 's/^#$//' -e 's/^# \?//'
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $arg" >&2
            echo "Run with --help for usage." >&2
            exit 2
            ;;
    esac
done

# --- Sanity ---

if [[ -z "$WIKI_DIR" ]]; then
    echo "ERROR: no wiki directory found. Pass --wiki=PATH or set WIKI_DIR." >&2
    echo "       Searched for $REPO_ROOT/wiki/*.wiki/." >&2
    exit 1
fi
if [[ ! -d "$WIKI_DIR" ]]; then
    echo "ERROR: wiki directory not found: $WIKI_DIR" >&2
    exit 1
fi
for tool in python3 riot arq curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not on PATH: $tool" >&2
        exit 1
    fi
done

mkdir -p "$CACHE_DIR" "$BUILD_DIR"

# --- Step 1: fetch / refresh spec from published URL ---

# Cache a file unless it is fresher than SPEC_CACHE_DAYS days
# (--refresh-spec always re-fetches). Falls back to cache on network
# failure when a cache exists.
fetch_spec() {
    local name="$1"
    local url="$SPEC_BASE_URL/$name"
    local cached="$CACHE_DIR/$name"

    local should_fetch=0
    if [[ -n "$REFRESH_SPEC" ]] || [[ ! -f "$cached" ]]; then
        should_fetch=1
    elif [[ -n "$(find "$cached" -mtime "+${SPEC_CACHE_DAYS}" 2>/dev/null)" ]]; then
        should_fetch=1
    fi

    if [[ "$should_fetch" -eq 1 ]]; then
        echo "  Fetching $url" >&2
        if curl -fsSL "$url" -o "$cached.tmp"; then
            mv "$cached.tmp" "$cached"
        else
            rm -f "$cached.tmp"
            if [[ -f "$cached" ]]; then
                echo "  WARN: fetch failed; using cached copy" >&2
            else
                echo "  ERROR: fetch failed and no cache available for $name" >&2
                exit 1
            fi
        fi
    else
        echo "  Using cached $cached" >&2
    fi
}

echo "=== scripts/kg/build-graph.sh ===" >&2
echo "wiki:        $WIKI_DIR" >&2
echo "spec source: $SPEC_BASE_URL" >&2
echo "cache:       $CACHE_DIR" >&2
echo "build:       $BUILD_DIR" >&2
echo "" >&2

echo "Step 1: Fetching / refreshing spec from $SPEC_BASE_URL ..." >&2
fetch_spec ontology.ttl
fetch_spec shapes.ttl
fetch_spec context.jsonld
echo "" >&2

ONTOLOGY="$CACHE_DIR/ontology.ttl"
SHAPES="$CACHE_DIR/shapes.ttl"
CONTEXT="$CACHE_DIR/context.jsonld"

# --- Step 2: extract frontmatter -> JSON-LD ---

echo "Step 2: Extracting frontmatter + body links -> JSON-LD ..." >&2

JSONLD_OUT="$BUILD_DIR/graph.jsonld"
python3 "$SCRIPT_DIR/wiki-to-jsonld.py" \
    --wiki "$WIKI_DIR" \
    --context "$CONTEXT" \
    --ontology "$ONTOLOGY" \
    --output "$JSONLD_OUT" \
    $STATS
echo "" >&2

# --- Step 3: JSON-LD -> Turtle ---

TURTLE_OUT="$BUILD_DIR/graph.ttl"
WEIGHTS_OUT="$BUILD_DIR/graph-weights.ttl"

echo "Step 3: Converting JSON-LD -> Turtle via riot ..." >&2
riot --syntax=jsonld --output=turtle "$JSONLD_OUT" 2>/dev/null > "$TURTLE_OUT"

if [[ -f "$WEIGHTS_OUT" ]]; then
    echo "" >> "$TURTLE_OUT"
    echo "# --- Weighted mentions (RDF-star) ---" >> "$TURTLE_OUT"
    cat "$WEIGHTS_OUT" >> "$TURTLE_OUT"
fi

echo "  Turtle lines: $(wc -l < "$TURTLE_OUT" | tr -d ' ')" >&2
echo "" >&2

# --- Step 4: materialise inverses, hubs, area inheritance ---

FULL_OUT="$BUILD_DIR/graph-full.ttl"
cp "$TURTLE_OUT" "$FULL_OUT"

if [[ -z "$SKIP_MATERIALIZE" ]]; then
    echo "Step 4: Materialising implied triples via arq CONSTRUCT ..." >&2
    INFERRED=$(mktemp)

    run_construct() {
        arq --data="$TURTLE_OUT" --query=<(echo "$1") 2>/dev/null \
          | riot --syntax=turtle --output=ntriples 2>/dev/null >> "$INFERRED"
    }

    PREFIX='PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>'

    # Area inheritance (propagates area down the up: hierarchy)
    run_construct "$PREFIX
CONSTRUCT { ?note llm-wiki-colab:area ?area }
WHERE {
    ?note llm-wiki-colab:up+ ?ancestor .
    ?ancestor llm-wiki-colab:area ?area .
    FILTER NOT EXISTS { ?note llm-wiki-colab:area ?area }
}"

    # Inverses of the forward predicates that have a declared owl:inverseOf
    for pair in \
        "supports:supportedBy" \
        "criticizes:criticizedBy" \
        "concept:conceptOf" \
        "partOf:hasPart" \
        "dependsOn:prerequisiteOf" \
        "defines:definedBy" \
        "resolvedBy:resolves" \
        "incorporatedInto:incorporates" \
        "outOfScopeFor:excludes" \
        "precedes:precededBy" \
        "feedsInto:informedBy"
    do
        fwd="${pair%:*}"
        inv="${pair#*:}"
        run_construct "$PREFIX
CONSTRUCT { ?t llm-wiki-colab:$inv ?s }
WHERE { ?s llm-wiki-colab:$fwd ?t }"
    done

    # Hub flag: pages with >=10 inbound non-mentions edges
    run_construct "$PREFIX
CONSTRUCT { ?note llm-wiki-colab:isHub true }
WHERE {
    { SELECT ?note (COUNT(?src) AS ?inbound) WHERE {
        ?src ?pred ?note .
        FILTER(?pred IN (llm-wiki-colab:up, llm-wiki-colab:area,
                         llm-wiki-colab:concept, llm-wiki-colab:source,
                         llm-wiki-colab:extends, llm-wiki-colab:supports,
                         llm-wiki-colab:criticizes, llm-wiki-colab:related))
    } GROUP BY ?note }
    FILTER(?inbound >= 10)
}"

    inferred_count=$(wc -l < "$INFERRED" | tr -d ' ')
    echo "  Materialised ~$inferred_count triples" >&2

    echo "" >> "$FULL_OUT"
    echo "# --- Materialised triples ---" >> "$FULL_OUT"
    cat "$INFERRED" >> "$FULL_OUT"
    rm "$INFERRED"

    echo "  Full graph lines: $(wc -l < "$FULL_OUT" | tr -d ' ')" >&2
    echo "" >&2
fi

# --- Step 5: SHACL validate ---

REPORT_OUT="$BUILD_DIR/validation-report.ttl"

if [[ -z "$SKIP_VALIDATE" ]]; then
    if ! command -v shacl >/dev/null 2>&1; then
        echo "WARN: shacl not on PATH; skipping validation step." >&2
    else
        echo "Step 5: SHACL validating $FULL_OUT against $SHAPES ..." >&2
        # SHACL may emit a non-zero exit on parse issues in the shapes
        # file; capture the report regardless and surface a summary.
        set +e
        shacl validate --shapes="$SHAPES" --data="$FULL_OUT" > "$REPORT_OUT" 2>&1
        set -e

        if grep -q "sh:conforms[[:space:]]*true" "$REPORT_OUT" 2>/dev/null; then
            echo "  Result: CONFORMS" >&2
        else
            violations=$(grep -c "sh:Violation" "$REPORT_OUT" 2>/dev/null || true)
            warnings=$(grep -c "sh:Warning"   "$REPORT_OUT" 2>/dev/null || true)
            echo "  Result: ${violations:-0} violations, ${warnings:-0} warnings" >&2
            echo "  Report: $REPORT_OUT" >&2
        fi
        echo "" >&2
    fi
fi

# --- Summary ---

echo "=== Build complete ===" >&2
ls -la "$BUILD_DIR" >&2

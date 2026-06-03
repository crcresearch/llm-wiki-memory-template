#!/usr/bin/env bash
# Unit test: knowledge-graph frontmatter pipeline.
#
# Runs scripts/kg/build-graph.sh against the fixture mini-wiki at
# scripts/kg/fixtures/mini-wiki and asserts on the produced JSON-LD,
# Turtle, and materialised triples.
#
# Dependencies are ASSERTED, not skipped. If python3, PyYAML, riot,
# arq, shacl, or curl are missing, this test fails. The CI workflow
# at .github/workflows/test-harness.yml installs them.

REPO_ROOT="$(cd "$HERE/../.." && pwd)"
KG_DIR="$REPO_ROOT/scripts/kg"
FIXTURE_WIKI="$KG_DIR/fixtures/mini-wiki"
BUILD_DIR="$KG_DIR/build"
BUILD_SCRIPT="$KG_DIR/build-graph.sh"

# --- Required tools on PATH ---

assert "python3 on PATH (kg extractor)"        "command -v python3"
assert "python3 yaml module installed"         "python3 -c 'import yaml'"
assert "riot on PATH (Apache Jena)"            "command -v riot"
assert "arq on PATH (Apache Jena)"             "command -v arq"
assert "shacl on PATH (Apache Jena)"           "command -v shacl"
assert "curl on PATH"                          "command -v curl"

# --- Required repo layout ---

assert "scripts/kg/build-graph.sh present and executable" \
    "[ -x '$BUILD_SCRIPT' ]"
assert "scripts/kg/wiki-to-jsonld.py present"  \
    "[ -f '$KG_DIR/wiki-to-jsonld.py' ]"
assert "scripts/kg/fixtures/mini-wiki/ present" \
    "[ -d '$FIXTURE_WIKI' ]"
assert "fixture mini-wiki has 5 .md files"     \
    "[ \$(find '$FIXTURE_WIKI' -maxdepth 1 -name '*.md' | wc -l | tr -d ' ') -eq 5 ]"

# --- Run the build against the fixture ---

KG_LOG="$SANDBOX/kg-build.log"
if "$BUILD_SCRIPT" --wiki="$FIXTURE_WIKI" --skip-validate >"$KG_LOG" 2>&1; then
    KG_RC=0
else
    KG_RC=$?
fi

assert "build-graph.sh against fixture exits 0" "[ '$KG_RC' -eq 0 ]"

if [ "$KG_RC" -ne 0 ]; then
    echo "  --- build-graph.sh output (tail) ---"
    tail -40 "$KG_LOG" | sed 's/^/    /'
    echo "  --- end output ---"
fi

# --- Output files exist and are non-empty ---

assert "build/graph.jsonld produced"           "[ -s '$BUILD_DIR/graph.jsonld' ]"
assert "build/graph.ttl produced"              "[ -s '$BUILD_DIR/graph.ttl' ]"
assert "build/graph-full.ttl produced"         "[ -s '$BUILD_DIR/graph-full.ttl' ]"

# --- JSON-LD shape: structural sanity ---

assert "graph.jsonld parses as JSON" \
    "python3 -c 'import json; json.load(open(\"$BUILD_DIR/graph.jsonld\"))'"

assert "graph.jsonld has @context and @graph" \
    "python3 -c '
import json
d = json.load(open(\"$BUILD_DIR/graph.jsonld\"))
assert \"@context\" in d
assert \"@graph\" in d
assert isinstance(d[\"@graph\"], list)
assert len(d[\"@graph\"]) >= 5
'"

# All five fixture pages must appear as nodes by @id
for slug in Home Concept-A Concept-B Source-X Untyped; do
    assert "graph.jsonld contains node @id=$slug" \
        "python3 -c '
import json
d = json.load(open(\"$BUILD_DIR/graph.jsonld\"))
ids = {n.get(\"@id\") for n in d[\"@graph\"]}
assert \"$slug\" in ids, f\"missing $slug; got {sorted(ids)}\"
'"
done

# --- Type mapping: frontmatter type -> ontology class IRI ---

assert "Concept-A type -> llm-wiki-colab:Concept" \
    "python3 -c '
import json
d = json.load(open(\"$BUILD_DIR/graph.jsonld\"))
n = next(n for n in d[\"@graph\"] if n[\"@id\"]==\"Concept-A\")
assert n[\"type\"] == \"llm-wiki-colab:Concept\", n[\"type\"]
'"

assert "Home type -> llm-wiki-colab:Index" \
    "python3 -c '
import json
d = json.load(open(\"$BUILD_DIR/graph.jsonld\"))
n = next(n for n in d[\"@graph\"] if n[\"@id\"]==\"Home\")
assert n[\"type\"] == \"llm-wiki-colab:Index\", n[\"type\"]
'"

assert "Source-X type -> llm-wiki-colab:SourceSummary" \
    "python3 -c '
import json
d = json.load(open(\"$BUILD_DIR/graph.jsonld\"))
n = next(n for n in d[\"@graph\"] if n[\"@id\"]==\"Source-X\")
assert n[\"type\"] == \"llm-wiki-colab:SourceSummary\", n[\"type\"]
'"

assert "Untyped (no frontmatter) -> llm-wiki-colab:UntypedNote" \
    "python3 -c '
import json
d = json.load(open(\"$BUILD_DIR/graph.jsonld\"))
n = next(n for n in d[\"@graph\"] if n[\"@id\"]==\"Untyped\")
assert n[\"type\"] == \"llm-wiki-colab:UntypedNote\", n[\"type\"]
'"

# --- Frontmatter typed edges resolve to @id refs ---

# Tiny inline helper: assert that page A has an edge `predicate` pointing
# at any of the listed target slugs.
assert_edge() {
    local desc="$1"
    local source="$2"
    local predicate="$3"
    local target="$4"
    assert "$desc" "python3 -c '
import json
d = json.load(open(\"$BUILD_DIR/graph.jsonld\"))
n = next(n for n in d[\"@graph\"] if n[\"@id\"]==\"$source\")
v = n.get(\"$predicate\")
if v is None:
    raise SystemExit(f\"$source has no $predicate edge\")
def ids(x):
    if isinstance(x, dict): return [x.get(\"@id\")]
    if isinstance(x, list): return [i.get(\"@id\") for i in x if isinstance(i, dict)]
    return [x]
assert \"$target\" in ids(v), f\"expected $target, got {ids(v)}\"
'"
}

assert_edge "Concept-A extends Concept-B"   Concept-A extends    Concept-B
assert_edge "Concept-A supports Concept-B"  Concept-A supports   Concept-B
assert_edge "Concept-A related Source-X"    Concept-A related    Source-X
assert_edge "Concept-A up Home"             Concept-A up         Home
assert_edge "Concept-B criticizes Concept-A" Concept-B criticizes Concept-A
assert_edge "Concept-B source Source-X"     Concept-B source     Source-X

# --- Materialised inverses appear in graph-full.ttl ---

assert "graph-full.ttl contains supportedBy (inverse of supports)" \
    "grep -q 'supportedBy' '$BUILD_DIR/graph-full.ttl'"

assert "graph-full.ttl contains criticizedBy (inverse of criticizes)" \
    "grep -q 'criticizedBy' '$BUILD_DIR/graph-full.ttl'"

# --- Both Turtle outputs parse via riot ---

assert "graph.ttl is well-formed Turtle"      \
    "riot --validate '$BUILD_DIR/graph.ttl'"

assert "graph-full.ttl is well-formed Turtle" \
    "riot --validate '$BUILD_DIR/graph-full.ttl'"

# scripts/kg/

Single-entry-point pipeline that builds a typed-edge knowledge graph
from the wiki's YAML frontmatter and body links. Implements what the
template's wiki page
[Knowledge-Graph-Pipeline](../../wiki/Knowledge-Graph-Pipeline)
previously documented as **NOT YET IMPLEMENTED**.

## Quick start

```bash
./scripts/kg/build-graph.sh                  # build against wiki/<repo>.wiki/
./scripts/kg/build-graph.sh --wiki=PATH      # custom wiki
./scripts/kg/build-graph.sh --refresh-spec   # re-fetch spec from LA3D
./scripts/kg/build-graph.sh --stats          # extractor stats
./scripts/kg/build-graph.sh --help           # full flag list
```

Outputs go to `scripts/kg/build/` (gitignored):

| File                    | Contents                                                  |
|-------------------------|-----------------------------------------------------------|
| `graph.jsonld`          | JSON-LD extracted from frontmatter + body links          |
| `graph.ttl`             | Turtle translation                                        |
| `graph-weights.ttl`     | RDF-star weighted `mentions`                              |
| `graph-full.ttl`        | `graph.ttl` plus materialised inverses, hubs, area inh.  |
| `validation-report.ttl` | SHACL conformance report                                 |

## Architecture

The pipeline distinguishes **spec** (canonical, fetched from the
published LA3D URL) from **code** (local, modifiable) and from
**queries** (curated subset that this template actually uses):

| Source of truth                                            | Files                                                  |
|------------------------------------------------------------|--------------------------------------------------------|
| `https://la3d.github.io/llm-wiki-colab/` (fetched at build, cached in `.cache/`) | `ontology.ttl`, `shapes.ttl`, `context.jsonld`         |
| Local to this template                                     | `build-graph.sh`, `wiki-to-jsonld.py`, `sparql/*.rq`   |
| Test fixtures                                              | `fixtures/mini-wiki/`                                  |

The published spec's IRIs (e.g. `llm-wiki-colab:Concept`,
`llm-wiki-colab:extends`) resolve under the
`https://la3d.github.io/llm-wiki-colab/ontology#` namespace. Anything
that needs the spec follows the IRI to its publisher. Vendoring would
create a second snapshot that would drift; instead we fetch on first
run and re-fetch when `--refresh-spec` is passed or the cache is older
than `SPEC_CACHE_DAYS` (default 7).

The build script and extractor live here as **local code, not vendored
dependency**. They are derived from prior work at
[LA3D/llm-wiki-colab](https://github.com/LA3D/llm-wiki-colab) (MIT) and
attribution is in each file's header. They evolve with the template;
upstream changes are not auto-tracked.

The `sparql/` directory is a **curated subset** of the LA3D query set,
selected for the multi-author wiki use case. PARA-organised
single-author primitives (`notes-by-area`, `projects-missing-area`,
`cross-moc-bridges`) and bibliographic queries (`literature-for-concept`,
`concept-chain`) are deliberately omitted; add them back if a use case
emerges.

## Dependencies

- Bash 4+
- Python 3 with PyYAML
- Apache Jena: `riot`, `arq`, `shacl` on PATH
- `curl`

Tests assert presence and fail on missing deps; the CI workflow in
`.github/workflows/test-harness.yml` installs them on `ubuntu-latest`
(Jena 5.2.0 tarball; `apt-get install python3-yaml`) and on
`macos-latest` (`brew install jena`; `pip3 install pyyaml`).

## Layout

```
scripts/kg/
├── README.md
├── build-graph.sh       single entry point
├── wiki-to-jsonld.py    frontmatter + body extractor (MIT, see header)
├── .gitignore           ignores .cache/ and build/
├── sparql/              11 canned queries (curated from LA3D set)
└── fixtures/mini-wiki/  5 fixture pages used by the harness assertions
```

Runtime-only (not committed):

```
scripts/kg/
├── .cache/              fetched spec (ontology.ttl, shapes.ttl, context.jsonld)
└── build/               graph.jsonld, graph.ttl, graph-full.ttl, validation-report.ttl
```

## Tests

The harness wraps a single assertion-set under
`scripts/test-mvp/tests/unit/kg-frontmatter-graph/assertions.sh`. Run
either:

```bash
./scripts/test-mvp/run.sh --category=unit          # via the harness
./scripts/test-mvp/run.sh kg-frontmatter-graph     # the single test
```

The assertions run `build-graph.sh --wiki=scripts/kg/fixtures/mini-wiki`
in a sandboxed `BUILD_DIR` and check the produced JSON-LD and Turtle for
expected pages, type mappings, frontmatter typed-edge resolution, and
materialised inverse edges.

## Scope today

- **Frontmatter typed edges**: fully exercised by the assertions
  (`up`, `extends`, `supports`, `criticizes`, `related`, `source`,
  plus all other LA3D forward predicates the extractor recognises).
- **Body link mentions**: extracted as `mentions` edges; the extractor
  also recognises Variant 1 inline annotations and HTML-comment
  attributes. These work today but are not the focus of the v1
  assertions.
- **SHACL validation**: runs against the fetched `shapes.ttl`. The
  build script does not abort on validation failures (the published
  shapes file currently has a known prefix-resolution issue that
  surfaces as a non-zero `shacl` exit; the report is written and
  surfaced regardless).
- **Federation / multi-wiki**: out of scope for this script. The IRIs
  the extractor mints use the LA3D base; multi-wiki federation is a
  separate design problem.

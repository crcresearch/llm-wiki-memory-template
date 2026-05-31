# Test Harness for llm-wiki-memory-template

Tests the proposed MVP updates to `crcresearch/llm-wiki-memory-template`
(captured at `Future-Template-MVP.md` in the wiki) AND the template's own
shipping scripts. Runs against either a real template clone (smoke tests)
or a simulated derivative (e2e MVP tests).

## Status

This harness lives on branch `llm-wiki-mvp-harness` in the `Omniscient_2`
repo. It is **not in main**. The Omniscient_2 main branch is grant-
submission work; this harness is template-tooling work that happens to be
developed here for convenience. When the MVP is contributed upstream, this
harness goes with it as a companion PR addressing template issue #5 (CI
for structural checks).

## What it tests

Organized by category. Each category runs in order: smoke first
(fast/structural), then e2e (full sandbox scenarios). Tests within a
category run alphabetically.

### Smoke (real template, fast structural checks)

| Test | Assertions | What it checks |
|---|---|---|
| `template-bootstrap` | 14 | Clones the real template, runs `instantiate.sh`, asserts: bash syntax of all shipping scripts, CLAUDE.md generated with substituted placeholders, wiki sub-repo created, namespaced nav files present, `init-wiki.sh` is idempotent |

### E2e (simulated derivative, MVP stage scenarios)

Per-stage assertions per the MVP spec's "Staged implementation plan" section:

| Stage | Assertions | What it tests |
|---|---|---|
| `stage1-identity` | 12 | Agent identity: `.claude/agent-id`, SessionStart hook, commit-msg trailer injector, Co-Authored-By + Agent-Instance trailers, instance ID variance/stability, custom handle override |
| `stage2-status-lint` | 14 | SCHEMA enrichment (CoALA, status lifecycle, curator fields, directional inverses), status-aware `wiki-lint-check.sh` covering all 5 statuses + curator orthogonality |
| `stage3-fetch-pull` | 10 | SessionStart fetches the wiki, auto-pulls on fast-forward, reports incoming, falls back on divergence |
| `stage4-collision-guard` | 15 | Pre-push hook installed in wiki repo; clean push succeeds; rebaseable push triggers rebase + abort + "re-run" message; conflicting push aborts with BLOCKED message + recovery sequence |
| `stage5-pre-write-awareness` | 13 | PreToolUse hook on wiki Edit/Write: silent when up-to-date, reports incoming with page names + author, silent on non-wiki paths, always exits 0 (non-blocking), handles missing fields defensively |
| `stage6-unified-vault` | 13 | SCHEMA namespacing mandate; lint accepts suffixed nav pages, flags unsuffixed `index.md` / `log.md` / `SCHEMA.md`; allows `Home.md` as redirect bridge but flags substantive content; two projects' nav pages coexist |

## Usage

```bash
# Run all categories (smoke + e2e), in order
./scripts/test-mvp/run.sh

# Run a specific category
./scripts/test-mvp/run.sh --category=smoke
./scripts/test-mvp/run.sh --category=e2e

# Run a specific test by name
./scripts/test-mvp/run.sh stage4-collision-guard

# Keep the sandbox dir after the run (for inspection)
./scripts/test-mvp/run.sh --no-cleanup
```

Exit code = number of failed assertions. 0 = all green.

## Template source

Smoke tests need a real template clone. Two ways to provide one:

```bash
# Offline mode (preferred for fast iteration; cheapest)
export MVP_TEMPLATE_LOCAL=~/Documents/projects/TCF/llm-wiki-memory-template
./scripts/test-mvp/run.sh

# Network mode (defaults to the chrissweet fork)
./scripts/test-mvp/run.sh

# Network mode with a different fork / branch
export MVP_TEMPLATE_REPO=https://github.com/your-fork/llm-wiki-memory-template.git
./scripts/test-mvp/run.sh
```

If neither is reachable, smoke tests `skip` gracefully and e2e still runs.

## Structure

```
scripts/test-mvp/
├── README.md           # this file
├── run.sh              # main entry point (categories, filtering, reporting)
├── lib/
│   ├── assert.sh       # assertion helpers (assert, assert_contains, assert_eq, assert_ne, skip)
│   ├── sandbox.sh      # sandbox lifecycle (mktemp + cleanup)
│   └── template.sh     # init_derivative (simulated) + clone_template (real)
└── tests/
    ├── smoke/
    │   └── template-bootstrap/
    │       ├── patch.sh       # clones template, runs instantiate.sh
    │       └── assertions.sh  # syntax + bootstrap-output assertions
    └── e2e/
        ├── stage1-identity/         { patch, assertions }
        ├── stage2-status-lint/      { patch, assertions }
        ├── stage3-fetch-pull/       { patch, assertions }
        ├── stage4-collision-guard/  { patch, assertions }
        ├── stage5-pre-write-awareness/  { patch, assertions }
        └── stage6-unified-vault/    { patch, assertions }
```

## Adding a test

1. Pick a category: `smoke` (fast/structural), `unit` (single-script), `integration` (multi-script), `e2e` (full sandbox), `regression` (test for a fixed bug).
2. `mkdir -p tests/<category>/<test-name>`
3. Write `patch.sh`: applies setup to the sandbox. Should be idempotent. Source `lib/template.sh` etc. if you need helpers (run.sh runs each `patch.sh` in a subshell).
4. Write `assertions.sh`: uses `assert` / `assert_contains` / `assert_eq` / `assert_ne` / `skip` helpers. Sourced by run.sh (so shares PASS/FAIL/FAILED_TESTS globals).
5. The harness auto-discovers by directory.

Categories run in order: smoke, unit, integration, e2e, regression (any other category runs after, alphabetically).

## CI

The harness is designed to run as a GitHub Actions workflow. A minimal
workflow (target: the fork or upstream when MVP merges):

```yaml
name: test-harness
on: [pull_request, push]
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install jq (Linux)
        if: matrix.os == 'ubuntu-latest'
        run: sudo apt-get install -y jq
      - run: ./scripts/test-mvp/run.sh
```

macOS in the matrix is important: stage 5 had two macOS-specific bugs
(symlink path resolution; wiki-toplevel detection) that wouldn't surface
on Linux. Run both.

## Design notes

- **Two modes of operation**: smoke tests use a real template clone (catches integration issues with the actual `init-wiki.sh`); e2e tests use a simulated derivative (fast iteration on MVP-specific behavior).
- **Patches are idempotent**: re-running an e2e test on a sandbox that already has its patch applied is a no-op.
- **Multi-machine scenarios are simulated**: copying the derivative to a second path gives a different `Agent-Instance` (different path hash).
- **Bash 3.2 compatible**: macOS default bash. No `mapfile`, careful with `set -u` and empty arrays.
- **What can't be tested here**: live Claude Code session behavior (whether the agent actually invokes the hook at the right moment). That requires either an LLM in the loop or a Claude-Code-compatible test harness that doesn't exist publicly today. Documented in the MVP spec's verification plan as Phase B (Omniscient_2 dry-run) and Phase C (cross-machine).

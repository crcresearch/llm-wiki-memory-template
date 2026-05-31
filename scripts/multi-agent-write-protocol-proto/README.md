# Multi-Agent Write Protocol — Deterministic Prototype

A bash prototype of the write protocol specified in the template wiki
page `Multi-Agent-Write-Protocol.md`. Exercises the protocol's mechanics
against a sandboxed git remote with two (or more) simulated agents, no
LLM in the loop. Validates that the git-merge layer behaves as the spec
claims it does before we invest in an LLM-driven version.

Status: prototype. Not wired into any agent overlay. Lives on the
`multi-agent-write-protocol-proto` branch of the Omniscient_2 repo; not
merged into `main`.

## Layout

```
scripts/multi-agent-write-protocol-proto/
├── README.md              this file
├── protocol.sh            protocol implementation (agent_write fn)
├── sandbox.sh             setup_sandbox / cleanup_sandbox / clone_for_agent
├── run-all.sh             runs every scenario; reports PASS/FAIL count
└── scenarios/
    ├── 01-different-pages/        two agents add unrelated pages
    ├── 02-different-sections/     two agents edit different sections of one page
    ├── 03-same-section/           two agents edit the same section (semantic conflict)
    ├── 04-index-union/            two agents both add new index entries
    ├── 05-log-append/             two agents both append log entries
    ├── 06-push-race/              two agents push simultaneously
    └── 07-livelock-retry/         third agent commits during retry; cap protects
```

Each scenario directory contains `run.sh` which:
1. Sources `sandbox.sh` and `protocol.sh`.
2. Sets up a sandbox.
3. Defines per-agent `changes_fn_*` (writes the agent's intended edits)
   and `resolve_fn_*` (deterministic semantic resolution for that
   scenario's conflict shape).
4. Drives the protocol via `agent_write` for each agent in the appropriate
   order.
5. Asserts the final state of `origin/main` matches the expectation.
6. Tears down the sandbox.

## Usage

```bash
# Run every scenario.
./run-all.sh

# Run a single scenario.
./scenarios/03-same-section/run.sh

# Keep the sandbox dir after a run (for inspection).
KEEP_SANDBOX=1 ./scenarios/03-same-section/run.sh
```

Exit code = number of failed scenarios. 0 = all green.

## What the prototype tests

The mechanics, not the LLM judgement. The "semantic resolution" step is
replaced with deterministic policies (e.g., "agent B's resolution appends
its content below agent A's existing content with an `### Update by ...`
header"). This is enough to verify:

- The git merge layer behaves as the spec assumes.
- Conflicts on `index_<repo>.md` and `log_<repo>.md` union-merge cleanly
  via `.gitattributes`.
- Push races are detected and retried.
- The retry cap halts cleanly on persistent conflict (scenario 07).
- The branch-per-attempt naming does not collide between agents.

What the prototype does NOT test:

- LLM-driven semantic reasoning over a real conflict. Deferred to a
  follow-up "LLM-driven prototype" that swaps the deterministic resolver
  for actual Claude sessions.
- The template's existing scripts and hooks. Those are exercised by the
  test harness on the `llm-wiki-mvp-harness` branch.
- Behavioural validation (does an agent actually invoke this protocol in
  a live session). Deferred.

## Compatibility

- macOS bash 3.2 and Linux bash 5+ both work (the existing test harness
  established this discipline; we follow it: no `mapfile`, careful with
  empty arrays and `set -u`).
- Requires `git`. Nothing else.

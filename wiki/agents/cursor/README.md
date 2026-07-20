# Cursor overlay for llm-wiki

Cursor-specific layer on top of the agent-agnostic llm-wiki core. Parallel to `wiki/agents/claude-code/`, both can be active in the same project.

> **⚠ Status: shipped but not yet validated in a live Cursor session.**
>
> Only the Claude Code overlay (`wiki/agents/claude-code/`) has been exercised end-to-end against a real agent. This overlay's `.cursor/rules/*.mdc` format, project skills under `.cursor/skills/`, `alwaysApply` semantics, and `sessionStart` hook are derived from Cursor's published documentation, not from observed behavior in a running Cursor IDE.
>
> If you are the first to try the Cursor path, please [open an issue](https://github.com/crcresearch/llm-wiki-memory-template/issues/new) reporting:
>
> - Cursor version (Cursor → About)
> - Whether the `wiki-experiment`, `wiki-source`, and `wiki-lint` skills appear and are applied when intent matches
> - Whether the `wiki-as-memory.mdc` rule (alwaysApply) is being injected into the agent's prompt
> - Whether the `sessionStart` hooks from `setup.sh --hook` (`ensure-wiki.sh` then `session-start.sh`) appear in the Hooks output channel and whether `additional_context` reaches the agent
> - Whether the `postToolUse` hook from `setup.sh --posttooluse-hook` fires after a wiki-page edit
> - Whether the agent honors the read/write/commit loop
> - Anything that does not match this README's "First-session walkthrough" further down
>
> Honest reports of failures are at least as useful as confirmations. The README content here is a hypothesis; your run is the test.

## What's here

| File | Purpose |
|---|---|
| `setup.sh` | Idempotent installer. Verifies the wiki, always-applied rule, and skills; patches `CLAUDE.md` (shares the marker with the Claude Code overlay so they don't double-patch); optionally installs the `sessionStart` and `postToolUse` hooks. |
| `templates/session-start-hook.sh` | Source for the Cursor `sessionStart` surfacing hook. Emitted as JSON `additional_context` (wiki orientation + index + last 5 log entries). |
| `templates/ensure-wiki-cursor.sh` | Source for the Cursor `sessionStart` ensure-wiki hook. A thin adapter over the shared `wiki/agents/templates/ensure-wiki.py`; clones the wiki sub-repo if absent (else fast-forwards it) and translates the shared script's output into Cursor's `additional_context` envelope. |
| `templates/posttooluse-hook.sh` | Source for the Cursor `postToolUse` advisory hook. After a Write/Edit to a wiki page it nudges the agent toward `discipline-gates.md` + `verification-gate.md` before committing. Advisory; never blocks. |

The shared, agent-agnostic `wiki/agents/templates/ensure-wiki.py` (used by both this overlay and Claude Code) does the real clone/fast-forward work; the Cursor adapter above only translates its output.

## Landing this overlay on a host

| Path | Command |
|---|---|
| New project | `instantiate.sh --agent=cursor` (or `--agent=all`) |
| Existing repo (first-time adopt) | `scripts/adopt.sh --target=. --apply --agent=cursor` |
| Add Cursor onto an already-adopted Claude host | `scripts/adopt.sh --target=. --apply --force --agent=cursor` |

Adopt ADDs the Cursor overlay files (substituting `{{REPO_NAME}}`), runs base `setup.sh`, applies default TOUCH grants (including `setup.sh --hook` for `.cursor/hooks.json`), and stamps `.cursorignore` when absent. Optional hooks beyond SessionStart (`--posttooluse-hook`, `--legacy`) remain manual: `./wiki/agents/cursor/setup.sh --posttooluse-hook`.

The actual Cursor configuration lives at the project root:

| Location | Purpose |
|---|---|
| `.cursor/rules/wiki-as-memory.mdc` | `alwaysApply: true`. Codifies the read/write/commit loop for the wiki. Equivalent to the CLAUDE.md "Wiki maintenance behavior" subsection but in Cursor's rules format. |
| `.cursor/skills/wiki-experiment/SKILL.md` | Project skill. Procedure for filing an experiment result. Applied when intent matches, or when asked for by name. |
| `.cursor/skills/wiki-source/SKILL.md` | Project skill. Procedure for ingesting a new source document. |
| `.cursor/skills/wiki-lint/SKILL.md` | Project skill. Procedure for health-checking the wiki. |
| `.cursor/hooks.json` + `.cursor/hooks/ensure-wiki.sh` + `.cursor/hooks/session-start.sh` | Installed by `setup.sh --hook`. Two `sessionStart` hooks in order: `ensure-wiki.sh` clones/fast-forwards the wiki sub-repo, then `session-start.sh` injects the index + recent log. |
| `.cursor/hooks/posttooluse-hook.sh` | Installed by `setup.sh --posttooluse-hook`. `postToolUse` advisory nudge after wiki-page writes (matcher `Write\|Edit`). |
| `.cursorignore` | Generated from `.cursorignore.template` by `instantiate.sh` (for `--agent=cursor\|all`) or by `scripts/adopt.sh --agent=cursor` when absent. Excludes duplicate Claude/Open-standard artifacts (`CLAUDE.md`, `.claude/`, `wiki/agents/claude-code/`) from Cursor indexing. Not present in this template-development repo (see "Controlling what Cursor sees"). |
| `.cursorrules.template` | Legacy single-file fallback for Cursor builds that don't read `.mdc` rules. Activate with `setup.sh --legacy`. |

## Flags

| Flag | What it does |
|---|---|
| (none) | Base mode: wiki verification + `CLAUDE.md` patch + rule/skills check |
| `--hook` | Installs `.cursor/hooks/ensure-wiki.sh` and `.cursor/hooks/session-start.sh` and registers both under `sessionStart` in `.cursor/hooks.json` (ensure-wiki first) |
| `--posttooluse-hook` | Installs `.cursor/hooks/posttooluse-hook.sh` and registers it under `postToolUse` with matcher `Write\|Edit`. Advisory gate nudge after wiki-page writes |
| `--legacy` | Installs `.cursorrules` from the template, substituting `{{REPO_NAME}}` |
| `--all` | `--hook` + `--posttooluse-hook` + `--legacy` |
| `-h`, `--help` | Prints the script's header comment |

## sessionStart hooks

Cursor supports project-level `sessionStart` hooks (see [Hooks docs](https://cursor.com/docs/hooks)). `setup.sh --hook` installs **two**, registered in order:

**1. `ensure-wiki.sh`** — a thin adapter over the shared `wiki/agents/templates/ensure-wiki.py`. It:

1. Runs the Python script, which clones the wiki sub-repo if it is absent (using the same VCS that manages this repo), or fast-forwards it to upstream when the checkout is clean.
2. Translates the script's Claude-format output (`hookSpecificOutput.additionalContext`) into Cursor's `{"additional_context": "..."}` envelope.
3. Fails open: any unexpected condition (no `python3`, script error, non-JSON output) emits `{"additional_context":""}` and exits 0, so it can never hang or error at session start.

**2. `session-start.sh`** — the surfacing hook. Once the wiki exists, it:

1. Always emits an orientation reminder (wiki path, commit discipline, project skills).
2. If `wiki/<repo>.wiki/index_<repo>.md` exists, appends the full index.
3. If `log_<repo>.md` exists, appends the last 5 log entries.
4. Wraps the result as `{"additional_context": "..."}` on stdout (required by Cursor; plain text is rejected).

ensure-wiki runs first so the wiki is present (and up to date) before the surfacing hook reads its index and log. Both fail open, so the order is an optimisation, not a correctness requirement.

`wiki-as-memory.mdc` (`alwaysApply: true`) remains the durable fallback if a given Cursor build drops `additional_context`. The hooks are what make the wiki feel like memory rather than search: the index is already in context at turn 0.

Requires `python3` (or `jq`) on `PATH` so the context can be JSON-escaped safely; `ensure-wiki.sh` additionally needs `python3` to run the shared script and degrades to a silent no-op without it.

## postToolUse hook

`setup.sh --posttooluse-hook` installs `.cursor/hooks/posttooluse-hook.sh` and registers it under `postToolUse` with matcher `Write|Edit`. After a Write or Edit to a wiki page (`wiki/<repo>.wiki/*.md`), it emits an `additional_context` reminder to:

1. Apply the discipline gates in [`wiki/agents/discipline-gates.md`](../discipline-gates.md) (the "Universal Rationalizations (Always Wrong)" table).
2. Run the Verification Gate procedure in [`wiki/agents/verification-gate.md`](../verification-gate.md) before committing in the wiki repo.

It is **advisory only** — per Cursor's hooks contract a `postToolUse` hook returns `additional_context` and does not block the action. It also cannot evaluate the wiki itself (a shell hook has no way to check corpus tags or back-references); it only reminds the agent, which has tools, to run the gates. The gate content is referenced, never duplicated, so it evolves in one place. This mirrors the Claude Code overlay's `posttooluse-hook.sh`. The `.cursor/rules/wiki-as-memory.mdc` rule stays lightweight; this hook is the only new gate-enforcement path for Cursor.

The matcher is a JavaScript regex on the tool type; the script also keeps a belt-and-suspenders path filter, so it stays correct even if the matcher is loosened.

## Verify the install

```bash
ls .cursor/rules/wiki-as-memory.mdc
ls .cursor/skills/wiki-*/SKILL.md   # wiki-{experiment,source,lint}
grep -n "Wiki maintenance" CLAUDE.md   # CLAUDE.md subsection present (shared with Claude Code overlay)
test -f .cursorrules && echo "legacy active" || echo "legacy not in use"
# After setup.sh --hook:
test -x .cursor/hooks/ensure-wiki.sh   && echo "ensure-wiki hook installed"
test -x .cursor/hooks/session-start.sh && echo "sessionStart surfacing hook installed"
jq '.hooks.sessionStart' .cursor/hooks.json   # ensure-wiki.sh listed BEFORE session-start.sh
# After setup.sh --posttooluse-hook:
test -x .cursor/hooks/posttooluse-hook.sh && echo "postToolUse hook installed"
jq '.hooks.postToolUse' .cursor/hooks.json    # matcher "Write|Edit"
```

## First-session walkthrough

Open Cursor in the project root, start a chat session, and try the following.

### 0. Sanity — skills discoverable

Ask Cursor to list project skills, or start a task that matches a skill description (e.g. "lint the wiki"). Confirm `wiki-experiment`, `wiki-source`, and `wiki-lint` are available under `.cursor/skills/`. If they are not applied when intent matches, check the Cursor version (modern builds support project skills); the always-applied `wiki-as-memory` rule remains as fallback.

### 0b. Sanity — sessionStart hooks (if `--hook` was installed)

Open the Hooks output channel (or Cursor Settings → Hooks) and start a **new** agent chat. Confirm both `ensure-wiki.sh` and `session-start.sh` ran (in that order) and returned valid JSON. If the wiki sub-repo was missing, `ensure-wiki.sh` should have cloned it. Ask a question that is answered by a page listed only in the index; the agent should not need an extra Read just to discover that page exists.

### 0c. Sanity — postToolUse hook (if `--posttooluse-hook` was installed)

Edit a wiki page in an agent chat, then check the Hooks output channel. Confirm `posttooluse-hook.sh` fired and injected a reminder pointing at `discipline-gates.md` and `verification-gate.md`. It is advisory: the edit proceeds regardless.

### 1. Read path — Query

Ask Cursor (in chat) a project-knowledge question without mentioning the wiki. Example: *"Summarize what we know about <topic central to the project>."*

**Expected:** the `wiki-as-memory` rule is always applied, so Cursor opens `index_{{REPO_NAME}}.md`, drills into named pages, and cites them. No skill invocation needed. With the sessionStart hook, the index may already be in context.

### 2. Write path — Ingest with auto-commit

Tell Cursor about a new finding from a script run, with the result path or command. Example: *"My new run produced X = 42 on the Y benchmark. Record it in the wiki. Output is at `experiments/results/run-NNN.json`."*

**Expected:** Cursor applies the `wiki-experiment` skill (its description matches the intent), reads existing pages to integrate, writes a synthesis page, updates index and log, and runs `git -C wiki/{{REPO_NAME}}.wiki add ... && git -C ... commit -m "..."` without an approval prompt. If your number is not backed by a real script output, the honest-reporting rule should make Cursor refuse to file it and ask for the evidence.

### 3. Explicit invocation — `wiki-experiment`

Same scenario, but name the skill explicitly (e.g. "use the wiki-experiment skill") to force the procedure even if the description match is uncertain.

### 4. Lint — `wiki-lint`

Ask for a wiki lint (or name the `wiki-lint` skill) and confirm Cursor scans the wiki, reports findings grouped by check type, and asks which to fix. Run this every few sessions or after a large ingest.

## What you've learned

| Trigger | When to use |
|---|---|
| `wiki-experiment` skill | A run finished. File metrics, config, and the diff against prior runs. |
| `wiki-source` skill | A new external document entered the project and you want it integrated. |
| `wiki-lint` skill | Periodic health check. Every few sessions or after a large ingest. |
| `sessionStart` hooks | Automatic. `ensure-wiki.sh` clones/fast-forwards the wiki, then `session-start.sh` injects index + recent log at turn 0 when `--hook` is installed. |
| `postToolUse` hook | Automatic. Advisory gate nudge after wiki-page writes when `--posttooluse-hook` is installed. |
| *(default)* | The `wiki-as-memory` rule is always applied; Cursor proactively reads and writes without needing a skill mention. |

## Sharing the CLAUDE.md subsection with the Claude Code overlay

Both overlays write the same "Wiki maintenance behavior" subsection into `CLAUDE.md`, using the same marker for idempotency. Whichever overlay's `setup.sh` runs first patches; the second one sees the marker and skips. The subsection is generic (it doesn't mention Claude Code or Cursor specifically); the agent-specific text lives in the rules / skills of each overlay.

## Controlling what Cursor sees

A Cursor target project has several complementary mechanisms for scoping what the agent indexes, reads, and gets injected with. Use the narrowest one that fits.

| Mechanism | What it controls | When to use |
|---|---|---|
| **`.cursorignore`** (project root, generated from `.cursorignore.template` during instantiate or adopt `--agent=cursor`) | Excludes paths from Cursor indexing / `@` context / agent file search | Avoid duplicate Claude/Open-standard artifacts in Cursor target projects; large artifacts, secrets, build outputs |
| **`.gitignore`** | Git tracking; adopt appends `wiki/*.wiki/` via grant | Keeps the wiki sub-repo out of main-repo git status; partial overlap with Cursor ignore |
| **Rule frontmatter** (`alwaysApply: false`, `globs:`) | Scope rules to matching files instead of every turn | Domain-specific guidance that should not bloat every session |
| **Project skills** (`.cursor/skills/*/SKILL.md`) | On-demand procedures vs always-injected rules | Heavy ingest/lint procedures — already used for `wiki-experiment`/`source`/`lint` |
| **Host-owned paths** (`TEMPLATE_HOST_OWNED`) | `update-from-template.sh` never overwrites | `CLAUDE.md`, `.gitignore`, `.cursor/hooks.json`, user hooks under `.cursor/hooks/` |
| **`beforeReadFile` hook** (optional, future) | Gate or deny reads of specific paths | Stricter than ignore — only if you need a hard block, not just de-prioritization |
| **User / team Cursor settings** | Global ignores, privacy mode | Secrets, dotfiles outside the repo; not checked into the template |

### `.cursorignore` in target projects

`instantiate.sh` stamps `.cursorignore.template` → `.cursorignore` when `--agent=cursor` or `--agent=all`, then removes the `.template` file. For `--agent=claude-code` or `--agent=none` the template is pruned outright. `scripts/adopt.sh --agent=cursor` stamps the same file when `.cursorignore` is absent (never overwrites). The generated file hides `CLAUDE.md`, `.claude/`, and `wiki/agents/claude-code/` — Cursor has its own native `.cursor/` rules and skills, so those parallel Claude instructions would be duplicate context.

This template-development repo intentionally does **not** carry a root `.cursorignore`: it is the workspace where both overlays are developed and must stay fully visible to any agent working on them.

Practical defaults for llm-wiki projects:

- Keep `wiki-as-memory.mdc` as `alwaysApply: true` (durable fallback).
- Use the generated `.cursorignore` to hide `.claude/`, `CLAUDE.md`, and `wiki/agents/claude-code/`.
- Do **not** hide the shared `wiki/agents/*.md` gate/protocol files (`discipline-gates.md`, `verification-gate.md`, `wiki-write-protocol.md`) or `wiki/agents/templates/ensure-wiki.py` — Cursor skills and the `postToolUse` hook reference them.
- Do **not** put the full verification-gate text in `alwaysApply` rules; let the `postToolUse` nudge + skills carry the depth.

## Updating after pulling template improvements

When `scripts/update-from-template.sh` syncs improvements from the template repo, it refreshes `.cursor/rules/wiki-as-memory.mdc`, `.cursor/skills/wiki-*/SKILL.md`, `wiki/agents/cursor/setup.sh`, `wiki/agents/cursor/templates/`, and the shared `wiki/agents/templates/ensure-wiki.py`. It does not touch `.cursorrules`, `.cursorignore`, `.cursor/hooks.json`, or `.cursor/hooks/` (those are install-time / one-shot artefacts from `setup.sh`, `instantiate.sh`, and `adopt.sh`). To refresh live hooks after a template update:

```bash
rm -f .cursor/hooks/ensure-wiki.sh .cursor/hooks/session-start.sh .cursor/hooks/posttooluse-hook.sh
./wiki/agents/cursor/setup.sh --hook --posttooluse-hook
```

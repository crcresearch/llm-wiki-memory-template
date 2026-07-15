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
> - Whether `setup.sh --hook` appears in the Hooks output channel and whether `additional_context` reaches the agent
> - Whether the agent honors the read/write/commit loop
> - Anything that does not match this README's "First-session walkthrough" further down
>
> Honest reports of failures are at least as useful as confirmations. The README content here is a hypothesis; your run is the test.

## What's here

| File | Purpose |
|---|---|
| `setup.sh` | Idempotent installer. Verifies the wiki, always-applied rule, and skills; patches `CLAUDE.md` (shares the marker with the Claude Code overlay so they don't double-patch); optionally installs the `sessionStart` hook. |
| `templates/session-start-hook.sh` | Source for the Cursor `sessionStart` hook. Emitted as JSON `additional_context` (wiki orientation + index + last 5 log entries). |

The actual Cursor configuration lives at the project root:

| Location | Purpose |
|---|---|
| `.cursor/rules/wiki-as-memory.mdc` | `alwaysApply: true`. Codifies the read/write/commit loop for the wiki. Equivalent to the CLAUDE.md "Wiki maintenance behavior" subsection but in Cursor's rules format. |
| `.cursor/skills/wiki-experiment/SKILL.md` | Project skill. Procedure for filing an experiment result. Applied when intent matches, or when asked for by name. |
| `.cursor/skills/wiki-source/SKILL.md` | Project skill. Procedure for ingesting a new source document. |
| `.cursor/skills/wiki-lint/SKILL.md` | Project skill. Procedure for health-checking the wiki. |
| `.cursor/hooks.json` + `.cursor/hooks/session-start.sh` | Installed by `setup.sh --hook`. Injects wiki index + recent log at every new agent session. |
| `.cursorrules.template` | Legacy single-file fallback for Cursor builds that don't read `.mdc` rules. Activate with `setup.sh --legacy`. |

## Flags

| Flag | What it does |
|---|---|
| (none) | Base mode: wiki verification + `CLAUDE.md` patch + rule/skills check |
| `--hook` | Installs `.cursor/hooks/session-start.sh` and registers it under `sessionStart` in `.cursor/hooks.json` |
| `--legacy` | Installs `.cursorrules` from the template, substituting `{{REPO_NAME}}` |
| `--all` | `--hook` + `--legacy` |
| `-h`, `--help` | Prints the script's header comment |

## sessionStart hook

Cursor supports a project-level `sessionStart` hook (see [Hooks docs](https://cursor.com/docs/hooks)). When installed, the script:

1. Always emits an orientation reminder (wiki path, commit discipline, project skills).
2. If `wiki/<repo>.wiki/index_<repo>.md` exists, appends the full index.
3. If `log_<repo>.md` exists, appends the last 5 log entries.
4. Wraps the result as `{"additional_context": "..."}` on stdout (required by Cursor; plain text is rejected).

`wiki-as-memory.mdc` (`alwaysApply: true`) remains the durable fallback if a given Cursor build drops `additional_context`. The hook is what makes the wiki feel like memory rather than search: the index is already in context at turn 0.

Requires `python3` or `jq` on `PATH` so the context can be JSON-escaped safely.

## Verify the install

```bash
ls .cursor/rules/wiki-as-memory.mdc
ls .cursor/skills/wiki-*/SKILL.md   # wiki-{experiment,source,lint}
grep -n "Wiki maintenance" CLAUDE.md   # CLAUDE.md subsection present (shared with Claude Code overlay)
test -f .cursorrules && echo "legacy active" || echo "legacy not in use"
# After setup.sh --hook:
test -x .cursor/hooks/session-start.sh && echo "sessionStart hook installed"
jq '.hooks.sessionStart' .cursor/hooks.json
```

## First-session walkthrough

Open Cursor in the project root, start a chat session, and try the following.

### 0. Sanity — skills discoverable

Ask Cursor to list project skills, or start a task that matches a skill description (e.g. "lint the wiki"). Confirm `wiki-experiment`, `wiki-source`, and `wiki-lint` are available under `.cursor/skills/`. If they are not applied when intent matches, check the Cursor version (modern builds support project skills); the always-applied `wiki-as-memory` rule remains as fallback.

### 0b. Sanity — sessionStart hook (if `--hook` was installed)

Open the Hooks output channel (or Cursor Settings → Hooks) and start a **new** agent chat. Confirm `session-start.sh` ran and returned valid JSON. Ask a question that is answered by a page listed only in the index; the agent should not need an extra Read just to discover that page exists.

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
| `sessionStart` hook | Automatic. Index + recent log at turn 0 when `--hook` is installed. |
| *(default)* | The `wiki-as-memory` rule is always applied; Cursor proactively reads and writes without needing a skill mention. |

## Sharing the CLAUDE.md subsection with the Claude Code overlay

Both overlays write the same "Wiki maintenance behavior" subsection into `CLAUDE.md`, using the same marker for idempotency. Whichever overlay's `setup.sh` runs first patches; the second one sees the marker and skips. The subsection is generic (it doesn't mention Claude Code or Cursor specifically); the agent-specific text lives in the rules / skills of each overlay.

## Updating after pulling template improvements

When `scripts/update-from-template.sh` syncs improvements from the template repo, it refreshes `.cursor/rules/wiki-as-memory.mdc`, `.cursor/skills/wiki-*/SKILL.md`, `wiki/agents/cursor/setup.sh`, and `wiki/agents/cursor/templates/`. It does not touch `.cursorrules`, `.cursor/hooks.json`, or `.cursor/hooks/` (those are install-time artefacts from `setup.sh --hook` / `--legacy`). To refresh a live hook after a template update:

```bash
rm -f .cursor/hooks/session-start.sh
./wiki/agents/cursor/setup.sh --hook
```

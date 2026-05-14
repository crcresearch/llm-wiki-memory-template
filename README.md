# llm-wiki-template

A template repository for the [llm-wiki pattern](https://github.com/tobi/llm-wiki), with optional overlays for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Cursor](https://docs.cursor.com/). The llm-wiki layer is agent-agnostic, so the same template also works in minimal mode for OpenCode, Pi, OpenInterpreter, or any agent you write yourself.

## 1. What this template gives you

- **A persistent, LLM-maintained wiki** as durable project memory (Query / Ingest / Lint operations). The wiki is its own git repository, separate from the project repo.
- **A skeleton `CLAUDE.md`** that any AI coding assistant reading repo-level instructions will find, codifying the read-to-recall / write-to-remember behavior.
- **Optional agent overlays** under `wiki/agents/<agent>/` that add slash commands, rules, settings, and personal memory seeds for a specific assistant. Today the template ships overlays for Claude Code and Cursor. Adding a new one (OpenCode, Pi, your own) follows a documented pattern.
- **Update tooling** so that projects instantiated from this template can pull in template improvements later without overwriting their own content.

## 2. Create a new project from this template

On GitHub, click **"Use this template" -> "Create a new repository"**, choose a name (e.g. `data-platform-notes`), then clone the new repo locally and run:

```bash
./scripts/instantiate.sh "My Project Name" --agent=claude-code
# other options: --agent=cursor, --agent=all, --agent=none
```

`instantiate.sh`:

1. Substitutes placeholders in `CLAUDE.md.template` (`{{PROJECT_NAME}}`, `{{REPO_NAME}}`, `{{DESCRIPTION}}`, `{{AGENT_NOTE}}`) and writes `CLAUDE.md`.
2. Runs `wiki/init-wiki.sh` to bootstrap the wiki sub-repository at `wiki/<repo-name>.wiki/`. Use `--github-wiki` if your project will host the wiki on GitHub's Wiki feature.
3. Runs the chosen overlay's `setup.sh` (Claude Code, Cursor, or both). Deletes the unused overlay directories.
4. Prints a checklist of files for you to edit by hand: the description and conventions in `CLAUDE.md`, the project `README.md`, etc.

If you pick `--agent=none`, only step 1 and 2 run. The minimal install leaves `.claude/`, `.cursor/`, and `wiki/agents/` populated but inert; you can activate (or remove) them later.

## 3. Pull updates from this template into an existing project

The llm-wiki pattern, the agent overlays, the slash commands and rules, and the instantiate/update scripts evolve in this template. Once you have created a project from the template, run this **periodically** to pull improvements without overwriting your own narrative:

```bash
./scripts/update-from-template.sh --dry-run    # preview what would change
./scripts/update-from-template.sh              # apply changes
```

**What it updates** (generic, shared content):

- `llm-wiki.md`, `wiki/init-wiki.sh`, `.gitignore`
- `wiki/agents/<agent>/setup.sh` and `wiki/agents/<agent>/templates/*` for every overlay present in the project
- `.claude/commands/wiki-*.md`, `.claude/skills/wiki-*.md` (only if `.claude/` exists in the project)
- `.cursor/rules/wiki-*.mdc` (only if `.cursor/` exists in the project)
- `scripts/instantiate.sh`, `scripts/update-from-template.sh`, `scripts/check-template-version.sh`

**What it does NOT touch** (project-specific content):

- `CLAUDE.md` (your project's narrative)
- `.cursorrules` (your project's narrative for Cursor)
- `README.md` (your project's user-facing docs)
- `.claude/settings.json` (your project's permissions)
- `.claude/hooks/` (per-machine hooks installed by `setup.sh --hook`)
- The wiki itself at `wiki/<your-repo>.wiki/` (separate git repo with its own history)
- Anything under your project source tree

After each run, an entry is appended to `.llm-wiki-template-log.md` (e.g. `## [2026-MM-DD] pulled template @<sha> -- N files updated`) so the sync history stays in the repo.

To check drift without making any changes:

```bash
./scripts/check-template-version.sh
```

## 4. Layout

```
llm-wiki-template/
  README.md                      this file
  CLAUDE.md.template             skeleton with {{PLACEHOLDERS}}
  llm-wiki.md                    the underlying pattern (read first)
  .gitignore                     ignores wiki sub-repo, settings.local.json, .venv
  .claude/                       Claude Code overlay artefacts
    commands/                    slash commands -- /wiki-experiment, /wiki-source, /wiki-lint
    skills/                      model-side procedure references
    settings.json.template       permissions allowlist for wiki-flow commands
  .cursor/                       Cursor overlay artefacts
    rules/                       Cursor's .mdc rules format
  .cursorrules.template          legacy Cursor format (single file)
  wiki/
    init-wiki.sh                 agent-agnostic wiki bootstrap
    agents/
      README.md                  how to add a new agent overlay
      claude-code/               Claude Code overlay: setup.sh + templates + docs
      cursor/                    Cursor overlay: setup.sh + templates + docs
  scripts/
    instantiate.sh               first-use bootstrap of a new project
    update-from-template.sh      pull generic + overlay updates from this template
    check-template-version.sh    read-only drift check
```

## 5. The three wiki operations (Query / Ingest / Lint)

The wiki has three operations: read it (Query), write to it (Ingest), and health-check it (Lint). All three are codified in:

- `CLAUDE.md` (the in-project AI guidance, generated from the template)
- The agent overlays (`/wiki-experiment`, `/wiki-source`, `/wiki-lint` for Claude Code; equivalent rules for Cursor)
- The wiki's own `SCHEMA_<repo>.md` (the authoritative procedures)

See [llm-wiki.md](llm-wiki.md) for the underlying pattern and [wiki/agents/README.md](wiki/agents/README.md) for the overlay structure.

## 6. Adding a new agent overlay (OpenCode, Pi, your own)

Each agent overlay lives in `wiki/agents/<agent>/` and follows a small contract documented in [wiki/agents/README.md](wiki/agents/README.md). To add support for a new agent:

1. Copy `wiki/agents/claude-code/` to `wiki/agents/<your-agent>/` as a starting point.
2. Adjust `setup.sh` to install the agent's project-level configuration files (its equivalent of `.claude/commands/`).
3. Update `templates/` with the agent-appropriate phrasings (rule format, command format, etc.).
4. Open a PR against this template repo so other projects in the organization can pick it up.

## 7. Contributing back

Improvements to the agent-agnostic parts (the llm-wiki pattern, `init-wiki.sh`, the schema, the scripts) are most valuable when they land here, in the template. Once merged, every project that runs `update-from-template.sh` will pick them up on the next sync.

For project-specific customizations, edit your project's `CLAUDE.md`, README, or settings -- those never propagate.

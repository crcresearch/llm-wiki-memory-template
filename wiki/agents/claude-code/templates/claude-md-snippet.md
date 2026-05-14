<!--
  Template: Wiki maintenance behavior subsection for CLAUDE.md.
  Injected by wiki/agents/claude-code/setup.sh into the ## Wiki section,
  immediately before the ### Knowledge Graph subsection.
  The setup script is idempotent: if the marker "### Wiki maintenance behavior"
  is already present in CLAUDE.md, the injection is skipped.
-->

### Wiki maintenance behavior

The wiki is this project's durable memory. Read it to recall context; write to it to remember. Apply this rule in both directions, proactively, without waiting to be asked.

- **Read** the wiki when context about the research would help an answer: start at `index_${REPO_NAME}.md`, then drill into named pages. Cite page names when synthesizing answers. If a wiki claim conflicts with current code or results, trust what is observed now and flag the stale page rather than repeating it.
- **Write** to the wiki whenever significant work produces something that a future session would benefit from knowing: experiment results (configuration, metrics per hop count where applicable, what changed, what was surprising), decisions with stated reasons, reusable syntheses, contradictions of prior claims. Follow the Ingest procedure in `SCHEMA_${REPO_NAME}.md`.

**Finish the cycle: every wiki edit ends with a commit.** The wiki at `wiki/${REPO_NAME}.wiki/` is a separate git repo with its own remote. After updating pages, run:

```bash
git -C wiki/${REPO_NAME}.wiki add <files-by-name>
git -C wiki/${REPO_NAME}.wiki commit -m "<descriptive message>"
```

Execute these without asking — local commits in the wiki repo are trivially reversible. Push only when explicitly asked.

Honest reporting: bad results and contradicted claims get filed truthfully, not polished. Per the global rule, never report accuracy from projections, only from real script outputs.

Claude Code users have project-level slash commands available for explicit invocation: `/wiki-experiment`, `/wiki-source`, `/wiki-lint`. See `.claude/commands/`. The project also ships the same procedures as model-side skills at `.claude/skills/` (referenced by the slash commands). The slash commands are a safety net: the proactive behavior described above is the default, the slash commands exist for cases where the user wants to force the action explicitly.

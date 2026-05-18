---
description: File experiment results to the wiki (Ingest procedure from SCHEMA).
---

You are filing an experiment result to the wiki as durable project memory.

Full procedure: see `.claude/skills/wiki-experiment.md` and `wiki/{{REPO_NAME}}.wiki/SCHEMA_{{REPO_NAME}}.md`. Summary:

1. Identify the experiment from the conversation or ask the user: which variant ran, configuration (parameters, seeds, dataset, scale, restart probability, type weights, softmax temperatures), headline metrics (per hop count for MuSiQue), what changed vs. the previous run, what was surprising, and the path to the experiment's `results/` directory.
2. Read existing wiki pages first (benchmark page, headline results page, comparison pages, concept pages whose claims this result bears on). Integrate, do not duplicate.
3. Create or update an experiment-results page with proper frontmatter (`type: synthesis` or `entity`; `up:` to the benchmark page; typed edges `supports:` / `criticizes:` / `extends:` when relevant).
4. Honest reporting: bad results filed truthfully, never report accuracy from projections, only from real script outputs.
5. Update concept pages whose claims this result bears on. If a result contradicts a wiki claim, update or flag the affected page.
6. Fix cross-references in both directions on every affected page.
7. Update `index_{{REPO_NAME}}.md` with one-line descriptions of new pages.
8. Append a `## [YYYY-MM-DD] update | Experiment name` entry to `log_{{REPO_NAME}}.md` with 2 to 5 bullets.
9. Optionally rebuild the knowledge graph: `./scripts/kg/build-graph.sh`.
10. **Run the Verification Gate** at `wiki/agents/verification-gate.md` over every page created or edited. Do not commit until all criteria pass. It catches projection-as-fact, missing corpus tags on numerical claims, missing back-references, and missing log/index entries.
11. **Finish the cycle.** Stage and commit in the wiki's own git repo, without asking:
    ```
    git -C wiki/{{REPO_NAME}}.wiki add <files-by-name>
    git -C wiki/{{REPO_NAME}}.wiki commit -m "<descriptive message>"
    ```
    Local commits are reversible. Push only if the user requests.

After filing, report which pages were created or updated, summarize the headline result in one sentence, and confirm the commit hash.

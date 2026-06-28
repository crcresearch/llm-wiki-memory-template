---
name: wiki-synthesize
description: Convert a migrated or freshly-populated wiki into memory-shaped content. Adds typed-edge frontmatter (extends / precedes / related / criticizes) to express connections between pages, creates hub pages to roll up clusters, writes a glossary for project jargon, and marks supersession-chain heads on Home. The second pass after `wiki-source` ingestion or `wiki-migrate` from an existing wiki — turns pages into knowledge.
---

A wiki of pages with `type:` / `up:` / `tags:` frontmatter is structurally valid but not yet memory-shaped. A future agent reading it sees the pages but not the connections between them: which experiment supersedes which, which concept defines a term used everywhere else, where the current best result lives. Synthesis is the pass that adds that connective tissue.

This skill complements `wiki-source` and `wiki-experiment` (which create individual pages) and `wiki-lint` (which keeps existing structure honest). It runs once per wiki when the page count is stable enough that synthesis is worth the cost, or after every major ingest batch.

## When to run

- After a `wiki-migrate` pass that brought in an existing external wiki verbatim with only `type:` / `up:` / `tags:` frontmatter.
- After 10+ new pages have been added by `wiki-source` / `wiki-experiment` without intermediate synthesis.
- When `wiki-lint` reports "many pages with only `up:` edge; no `extends` / `precedes` / `related`."
- When the user asks how to find the head of an experiment chain, or what a project-specific term means, and the wiki can't answer cheaply.

## What the synthesis pass produces

1. **Typed-edge frontmatter** on existing pages: `extends`, `precedes`, `related`, `criticizes`. These capture connections the pages already imply but don't yet express. The KG pipeline consumes these for structural queries.
2. **Hub pages** for clusters of 3 or more related pages. A hub names the cluster, lists its members with one-line characterizations, identifies the head of any supersession chain inside it, and surfaces what the cluster collectively teaches. New `type: synthesis` pages.
3. **A glossary page** for project-specific jargon — terms that appear in 3 or more pages without a defining page. New `type: reference` page.
4. **A Current-State section on `Home_{{REPO_NAME}}.md`** identifying the head of each supersession chain, the best result in scope of the project, and any explicit open questions surfaced in page bodies.
5. **Index updates** to list the new hubs and glossary.
6. **A log entry** attributing the synthesis pass.

## Procedure

1. **Read every page** in `wiki/{{REPO_NAME}}.wiki/`. Build a per-page summary: title, opening paragraph, key result line if any, named entities (datasets, methods, models, drugs, people), dates, references to other pages.
2. **Detect clusters** using three signals (most-specific first):
   - Filename prefix groups (`Experiment-`, `DVC-`, `CRS-Set-`, etc.) — strong signal.
   - Tag overlap: 3 or more pages sharing a non-generic tag.
   - Vocabulary overlap: 3 or more pages mentioning the same dataset, model architecture, drug, or methodology.
3. **Propose typed edges** to the user as a table — source → predicate → target, plus the prose snippet that supports each. Apply user-approved edges as frontmatter updates. Predicate selection:
   - `precedes` for explicit sequences (numbered experiments, dated re-runs, "after X" phrasing).
   - `extends` for intellectual lineage ("the Y variant of," "applies the X approach to," "computes Z on top of").
   - `related` for siblings (same prefix, no clear lineage).
   - `criticizes` when one page argues against another's claim or identifies a flaw.
   - Default to no annotation when unsure. Sparse-accurate beats dense-speculative.
4. **Propose hub pages** for each cluster of 3+ pages. Show the user an outline before writing: cluster name, member list with one-line characterizations, supersession-head identification, "what the cluster teaches" prose. Re-parent member pages' `up:` to the hub after the user approves.
5. **Propose a glossary** by extracting candidate jargon: tokens appearing in 3+ page bodies, not in a common-English filter, not already a wiki page title. Group definitions by category (datasets, methods, metrics, tooling, people). Cross-link from glossary entries to the pages where each term is used substantively.
6. **Update `Home_{{REPO_NAME}}.md`** with a Current-State section: head of each supersession chain, best-result-in-scope (extracted from page bodies), open questions.
7. **Update `index_{{REPO_NAME}}.md`** to list new hubs and the glossary near the top, before the topic-grouped sections.
8. **Run `wiki-lint`** to verify no orphans created, no dead links, all new pages have proper frontmatter, all bidirectional links honored where the design requires them.
9. **Append a `## [YYYY-MM-DD] synthesize | Subject` log entry** to `log_{{REPO_NAME}}.md` describing the edges added, hubs created, and glossary scope. First bullet is the attribution line `- by: <name> via claude-code`, where `<name>` is the output of `git config user.name` in the wiki repo.
10. **Commit in two steps** in the wiki's own git repo: page changes + index first, then the log entry on its own. Do not push unless asked. **When pushing, follow the procedure at `wiki/agents/wiki-write-protocol.md`** rather than plain `git push`.

## Stop-and-confirm checkpoints

The synthesis pass is judgment-heavy. Stop and confirm with the user at three points:

- After **edge proposals** (step 3). Show a table; user approves or rejects each before frontmatter is touched.
- After **hub outlines** (step 4). Show the proposed cluster name, members, and head-of-chain pick before any body is written.
- Before **commit** (step 10). Show the diff summary so the user sees the full scope of the pass.

## Where agent judgment is load-bearing

Synthesis cannot be reduced to mechanical rules. The agent must read prose and choose:

- **`precedes` vs `extends` vs `related`.** Sequence vs intellectual lineage vs siblings. Often the prose says it explicitly ("Since the X data has changed, we will re-run") but sometimes it requires inference.
- **Cluster granularity.** One big "Methods" hub or split into "Preprocessing" and "Feature-Engineering"? Depends on whether the cluster's prose naturally tells one story or two.
- **What counts as a chain head.** When multiple branches are live, the "head" is project-decision territory; default to the most recent, but surface the ambiguity to the user.
- **Whether a triage / notes page is `criticizes` or just `related`.** If the page literally argues specific claims are wrong, `criticizes`. If it raises concerns without taking a position, `related`.
- **Glossary inclusion.** Project jargon (PAD, EBM, dE/dx) belongs in. Generic terms (training, model, batch size) do not. The threshold is "would a new lab member need this defined."

When in doubt, leave the annotation off. Sparse-accurate edges are recoverable on a future synthesis pass; dense-speculative ones erode trust in the KG.

## Honest reporting

Do not invent connections to make the wiki look richer. A spurious `extends` claim distorts every downstream query that consumes `extends` edges; a wrong "head of chain" mark on Home misleads a future agent reading current state. If a page's relationship to others is genuinely unclear, leave it standalone and flag the ambiguity to the user instead of guessing.

For supersession chains, the "current head" claim is load-bearing — a future agent will trust it. If you can't determine the head with confidence, mark it as "candidate heads" with two or three names and let the user resolve.

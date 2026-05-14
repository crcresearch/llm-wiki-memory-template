#!/usr/bin/env bash
#
# Claude Code SessionStart hook: prints a system-reminder that this project
# uses the wiki as durable memory, and that the read-write loop ends with a
# commit in the wiki's own git repo. Installed by setup.sh --hook into
# .claude/hooks/session-start.sh, then referenced from .claude/settings.json.
#
# The hook is opt-in because it adds a small amount of text to every
# session start. If the user has already internalized the rule (via
# CLAUDE.md + .claude/skills/), the hook is redundant.
#
# Stdout from this script is captured by Claude Code and surfaced as a
# system-reminder in the model's context at the start of each session.
#

cat <<'EOF'
<system-reminder>
This project uses the wiki at wiki/${REPO_NAME}.wiki/ as durable memory.
It is a separate git repository with its own remote, NOT a subdirectory of
the main repo. Read SCHEMA_${REPO_NAME}.md before non-trivial wiki edits.
Update the wiki proactively when experiment results, decisions, or
syntheses emerge.

Every wiki edit ends with a commit in the wiki's own repo:
  git -C wiki/${REPO_NAME}.wiki add <files>
  git -C wiki/${REPO_NAME}.wiki commit -m "..."
Run these without asking — local commits are reversible. Push only on
explicit request.

Slash commands available: /wiki-experiment, /wiki-source, /wiki-lint.
</system-reminder>
EOF

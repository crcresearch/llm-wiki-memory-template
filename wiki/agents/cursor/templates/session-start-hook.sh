#!/usr/bin/env bash
#
# Cursor sessionStart hook: surfaces this project's wiki at the start of
# every agent session so the agent treats the wiki as compounding memory
# rather than as on-demand RAG.
#
# Cursor command hooks must emit a single JSON object on stdout. This
# script builds the same three content blocks as the Claude Code
# SessionStart hook, then wraps them as:
#
#   {"additional_context": "<blocks>"}
#
# Blocks (markdown inside additional_context):
#
#   1. Orientation reminder. Tells the agent the wiki exists, where it
#      lives, the read/write loop, and the commit discipline. Constant
#      text; safe even if the wiki sub-repo is absent.
#
#   2. The wiki's index page. Catalog of every page in the wiki, with
#      one-line descriptions. With the index in context at turn 0, the
#      agent answers wiki-pageable questions without an extra Read/Grep
#      tool call. The wiki becomes memory, not search.
#
#   3. The last 5 log entries. Recent activity gives the agent enough
#      continuity from prior sessions to pick up mid-thread.
#
# Blocks 2 and 3 are skipped silently if the wiki sub-repo has not been
# initialised yet, so the hook is safe to install before init-wiki.sh
# runs. The cost is a few thousand tokens at session start, paid once,
# in exchange for the wiki actually functioning as memory.
#
# Installed by wiki/agents/cursor/setup.sh --hook into
# .cursor/hooks/session-start.sh, with ${REPO_NAME} substituted at
# install time.
#
# Requires python3 (or jq) to JSON-escape the context. If neither is
# available the hook emits {"additional_context":""} rather than
# invalid JSON that Cursor would reject.
#

set -euo pipefail

# Consume stdin (Cursor sends sessionStart input JSON). We do not need
# the payload today; draining it avoids a broken-pipe warning.
cat >/dev/null

emit_json() {
    # stdin is the assembled markdown context from the caller pipeline.
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys; print(json.dumps({"additional_context": sys.stdin.read()}))'
    elif command -v jq >/dev/null 2>&1; then
        jq -Rs '{additional_context: .}'
    else
        cat >/dev/null
        echo '{"additional_context":""}'
    fi
}

{
    # Block 1: orientation reminder (always emitted).
    cat <<'EOF'
## Wiki as project memory (session start)

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

Project skills: wiki-experiment, wiki-source, wiki-lint.
EOF

    # Block 2: wiki index, if the wiki sub-repo exists.
    INDEX_FILE="wiki/${REPO_NAME}.wiki/index_${REPO_NAME}.md"
    if [[ -f "$INDEX_FILE" ]]; then
        echo
        echo "## Wiki current state — index"
        echo
        cat "$INDEX_FILE"
    fi

    # Block 3: last 5 log entries, if the log exists. The log is append-only
    # with newest at the bottom, so "last 5" means the 5 most recent.
    LOG_FILE="wiki/${REPO_NAME}.wiki/log_${REPO_NAME}.md"
    if [[ -f "$LOG_FILE" ]]; then
        TOTAL_ENTRIES=$(grep -c '^## \[' "$LOG_FILE" 2>/dev/null || echo 0)
        START_ENTRY=1
        if [[ "$TOTAL_ENTRIES" -gt 5 ]]; then
            START_ENTRY=$((TOTAL_ENTRIES - 4))
        fi
        echo
        echo "## Wiki current state — last 5 log entries"
        echo
        awk -v s="$START_ENTRY" '/^## \[/{c++} c>=s' "$LOG_FILE"
    fi
} | emit_json

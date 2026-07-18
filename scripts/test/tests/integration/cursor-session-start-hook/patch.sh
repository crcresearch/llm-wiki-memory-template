#!/usr/bin/env bash
# Integration test patch: Cursor sessionStart hook JSON injection.
#
# Stages two fake derived projects in the sandbox so assertions.sh can
# verify the Cursor hook's JSON additional_context behaviour:
#
#   $SANDBOX/cursor-session-start-hook/fakerepo/         — wiki present
#   $SANDBOX/cursor-session-start-hook/fakerepo-nowiki/  — wiki absent
#
# The hook is rendered via the same sed substitution that
# wiki/agents/cursor/setup.sh applies at install time.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
HOOK_TEMPLATE="$REPO_ROOT/wiki/agents/cursor/templates/session-start-hook.sh"

if [ ! -f "$HOOK_TEMPLATE" ]; then
    echo "  Cursor hook template not found at $HOOK_TEMPLATE" >&2
    exit 1
fi

STAGE_DIR="$SANDBOX/cursor-session-start-hook"
mkdir -p "$STAGE_DIR"

FAKE_DIR="$STAGE_DIR/fakerepo"
WIKI_SUB="$FAKE_DIR/wiki/fakerepo.wiki"
mkdir -p "$WIKI_SUB"

cat > "$WIKI_SUB/index_fakerepo.md" <<'EOF'
---
type: index
up: "[[Home_fakerepo]]"
---

# Index — fakerepo

Catalog of all wiki pages.

## Overview
- [Home](Home_fakerepo) — Project summary

## Concepts
- [Test-Concept-Alpha](Test-Concept-Alpha) — sentinel page for index injection
EOF

cat > "$WIKI_SUB/log_fakerepo.md" <<'EOF'
---
type: index
up: "[[Home_fakerepo]]"
---

# Log — fakerepo

Chronological record of wiki activity.

## [2026-01-01] create | Entry 1 — oldest, should NOT appear in hook output
- by: Test User via cursor
- This is the oldest entry. With 7 entries total and last-5 logic, it gets skipped.

## [2026-01-02] ingest | Entry 2 — also too old, should NOT appear
- by: Test User via cursor
- Second-oldest. Also skipped.

## [2026-02-01] ingest | Entry 3 — first of the last 5
- by: Test User via cursor
- The hook output should START here.

## [2026-03-01] ingest | Entry 4
- by: Test User via cursor
- Mid-range entry.

## [2026-04-01] lint | Entry 5
- by: Test User via cursor
- Mid-range entry.

## [2026-05-01] ingest | Entry 6
- by: Test User via cursor
- Mid-range entry.

## [2026-06-01] ingest | Entry 7 — most recent
- by: Test User via cursor
- Newest entry, at the bottom of the file.
EOF

sed 's/\${REPO_NAME}/fakerepo/g' "$HOOK_TEMPLATE" > "$FAKE_DIR/hook.sh"
chmod +x "$FAKE_DIR/hook.sh"

NOWIKI_DIR="$STAGE_DIR/fakerepo-nowiki"
mkdir -p "$NOWIKI_DIR"
sed 's/\${REPO_NAME}/fakerepo-nowiki/g' "$HOOK_TEMPLATE" > "$NOWIKI_DIR/hook.sh"
chmod +x "$NOWIKI_DIR/hook.sh"

# --- ensure-wiki-cursor.sh adapter fixtures ---
# The adapter runs `python3 wiki/agents/templates/ensure-wiki.py` from cwd and
# translates the shared script's Claude-format stdout into Cursor's
# {"additional_context": ...} envelope. To test the translation in isolation
# (no real wiki, no network), each fixture ships a FAKE ensure-wiki.py at the
# path the adapter invokes:
#   adapter-nudge/   fake emits Claude SessionStart JSON -> adapter must
#                    re-wrap the message as additional_context.
#   adapter-silent/  fake emits nothing (success path) -> adapter must emit
#                    {"additional_context":""}.
ADAPTER_TEMPLATE="$REPO_ROOT/wiki/agents/cursor/templates/ensure-wiki-cursor.sh"
if [ -f "$ADAPTER_TEMPLATE" ]; then
    NUDGE_DIR="$STAGE_DIR/adapter-nudge"
    mkdir -p "$NUDGE_DIR/wiki/agents/templates"
    cp "$ADAPTER_TEMPLATE" "$NUDGE_DIR/ensure-wiki.sh"
    chmod +x "$NUDGE_DIR/ensure-wiki.sh"
    cat > "$NUDGE_DIR/wiki/agents/templates/ensure-wiki.py" <<'PYEOF'
import json, sys
json.dump({"hookSpecificOutput": {"hookEventName": "SessionStart",
          "additionalContext": "CLONE THE WIKI at wiki/canonical.wiki/"}}, sys.stdout)
PYEOF

    SILENT_DIR="$STAGE_DIR/adapter-silent"
    mkdir -p "$SILENT_DIR/wiki/agents/templates"
    cp "$ADAPTER_TEMPLATE" "$SILENT_DIR/ensure-wiki.sh"
    chmod +x "$SILENT_DIR/ensure-wiki.sh"
    cat > "$SILENT_DIR/wiki/agents/templates/ensure-wiki.py" <<'PYEOF'
import sys
sys.exit(0)
PYEOF
fi

echo "  Cursor session-start-hook patch staged: fakerepo (with wiki) + fakerepo-nowiki (without) + ensure-wiki adapter fixtures."

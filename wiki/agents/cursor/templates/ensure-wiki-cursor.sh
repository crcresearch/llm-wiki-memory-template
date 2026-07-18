#!/usr/bin/env bash
#
# Cursor sessionStart hook: ensure the project's durable-memory wiki is
# present. This is a thin adapter over the agent-agnostic
# wiki/agents/templates/ensure-wiki.py, which does the real work (clone the
# wiki sub-repo if absent, else fast-forward it when the checkout is clean,
# using the same VCS that manages this repo). The Python script is shared
# with the Claude Code overlay; only the stdout envelope differs between the
# two agents, so this wrapper translates:
#
#   ensure-wiki.py emits (Claude SessionStart form):
#     {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
#   Cursor sessionStart expects:
#     {"additional_context":"..."}
#
# ensure-wiki.py is silent on the success path (wiki cloned/updated, or
# nothing to do), and only prints when it needs to nudge the agent (clone
# failed, or the wiki is behind and cannot be fast-forwarded). This adapter
# maps silence to {"additional_context":""} and a nudge to
# {"additional_context": <message>}.
#
# Installed by wiki/agents/cursor/setup.sh --hook into
# .cursor/hooks/ensure-wiki.sh, registered BEFORE session-start.sh so the
# wiki exists (and is fast-forwarded) before the surfacing hook reads its
# index and log. Copied verbatim: it uses paths relative to the repo root
# and needs no ${REPO_NAME} substitution.
#
# Fail-open contract, matching ensure-wiki.py: any unexpected condition
# (no python3, script error, non-JSON stdout) degrades to an empty
# additional_context and exit 0, never invalid JSON or a non-zero status
# that would surface as a hook error at session start.
#

set -uo pipefail

# Drain stdin (Cursor sends sessionStart input JSON). The payload is not
# needed today; draining it avoids a broken-pipe warning.
cat >/dev/null

emit_empty() {
    printf '%s\n' '{"additional_context":""}'
    exit 0
}

# Without python3 there is no way to run ensure-wiki.py (nor to JSON-escape
# safely); degrade to a silent success rather than erroring.
command -v python3 >/dev/null 2>&1 || emit_empty

ENSURE_PY="wiki/agents/templates/ensure-wiki.py"
[[ -f "$ENSURE_PY" ]] || emit_empty

# Run the shared script from the repo root. It resolves the repo root itself
# via git, so cwd only needs to be inside the working tree.
RAW="$(python3 "$ENSURE_PY" 2>/dev/null)" || emit_empty

# Silent success path: nothing to surface.
[[ -z "$RAW" ]] && emit_empty

# Translate the Claude SessionStart envelope into Cursor's. If the payload is
# not the expected shape, fall back to an empty context (never invalid JSON).
printf '%s' "$RAW" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    msg = data.get("hookSpecificOutput", {}).get("additionalContext", "")
except Exception:
    msg = ""
print(json.dumps({"additional_context": msg if isinstance(msg, str) else ""}))
' || emit_empty

exit 0

#!/usr/bin/env bash
#
# Cursor postToolUse hook (advisory): after a Write or Edit to a wiki page,
# remind the agent to apply the discipline gates and run the Verification
# Gate procedure before committing in the wiki repo. Installed by
# wiki/agents/cursor/setup.sh --posttooluse-hook into
# .cursor/hooks/posttooluse-hook.sh (with ${REPO_NAME} substituted at install
# time), registered in .cursor/hooks.json under postToolUse with matcher
# "Write|Edit".
#
# Advisory only, mirroring the Claude Code posttooluse-hook.sh contract: per
# Cursor's hooks docs a postToolUse hook returns additional_context (it does
# not block the action). This script does not — and cannot — evaluate the
# wiki itself; a shell hook has no way to check back-references, corpus tags,
# or index/log state. It only injects a reminder pointing the agent, which
# has tools, at the canonical gate documents:
#
#   - wiki/agents/discipline-gates.md   (Universal Rationalizations + gates)
#   - wiki/agents/verification-gate.md  (pre-commit criteria checklist)
#
# Those files are agent-agnostic shared infra, referenced (not duplicated)
# here so the criteria evolve in one place.
#
# Reads the postToolUse event JSON on stdin. Always emits a single JSON
# object with an additional_context field (empty for non-wiki writes) and
# exits 0.
#

set -uo pipefail

INPUT=$(cat)

emit() {  # stdin = additional_context message (may be empty)
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys; print(json.dumps({"additional_context": sys.stdin.read()}))'
    elif command -v jq >/dev/null 2>&1; then
        jq -Rs '{additional_context: .}'
    else
        # No JSON escaper available: emit an empty context rather than risk
        # invalid JSON that Cursor would reject.
        cat >/dev/null
        printf '%s\n' '{"additional_context":""}'
    fi
}

# Extract the path of the file just written or edited (.tool_input.file_path,
# the same field Claude Code uses). Prefer jq; fall back to python3 so the
# hook still nudges on a host that has python3 but not jq. Empty if neither
# is available or the field is absent; either way the script simply does not
# nudge.
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
elif command -v python3 >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("file_path", "") or "")
except Exception:
    print("")' 2>/dev/null || true)
fi

# Nudge only for a write/edit to a wiki page: wiki/<repo>.wiki/*.md.
case "$FILE_PATH" in
    *wiki/*.wiki/*.md)
        emit <<'EOF'
A wiki page was just written or edited. Before committing in the wiki repo:

1. Apply the discipline gates in wiki/agents/discipline-gates.md — check every
   write against the "Universal Rationalizations (Always Wrong)" table.
2. Run the Verification Gate procedure in wiki/agents/verification-gate.md over
   every page created or edited this session: every numerical claim tagged with
   its corpus, every projection marked as such, back-references bidirectional,
   and index_${REPO_NAME}.md plus log_${REPO_NAME}.md updated.

This is an advisory reminder and does not block.
EOF
        exit 0
        ;;
esac

# Non-wiki write (or no path): emit an empty additional_context.
printf '' | emit
exit 0

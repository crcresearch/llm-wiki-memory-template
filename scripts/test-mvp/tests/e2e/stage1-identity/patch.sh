#!/usr/bin/env bash
# Stage 1: Agent identity patch.
# Applies to a sandbox derivative (created by init_derivative).
#
# Inputs:  SANDBOX env var pointing at the sandbox root.
# Effects: adds .claude/agent-id, installs the SessionStart hook script,
#          runs the hook once to install the commit-msg trailer-injector.

set -euo pipefail

D="$SANDBOX/derivative"

# 1. Write .claude/agent-id (one-line canonical handle)
HUMAN=$(cd "$D" && git config user.email | cut -d@ -f1)
PROJECT=$(basename "$D")
cat > "$D/.claude/agent-id" <<EOF
# Canonical handle for this project's claude-code agent.
# Format: claude-<human>@<project>
claude-${HUMAN}@${PROJECT}
EOF

# 2. Install the SessionStart hook script
cat > "$D/.claude/hooks/session-start.sh" <<'SS_EOF'
#!/usr/bin/env bash
# Stage 1: agent identity only.
# Reads .claude/agent-id, computes instance ID, installs commit-msg hook
# that injects Co-Authored-By and Agent-Instance trailers.
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[ -z "$PROJECT_ROOT" ] && exit 0
cd "$PROJECT_ROOT"

# Read handle from .claude/agent-id, or compute it
if [ -f .claude/agent-id ]; then
    HANDLE=$(grep -v '^#' .claude/agent-id | grep -v '^[[:space:]]*$' | head -n1 | tr -d '[:space:]')
else
    HUMAN=$(git config user.email | cut -d@ -f1)
    PROJECT=$(basename "$PROJECT_ROOT")
    HANDLE="claude-${HUMAN}@${PROJECT}"
fi

# Compute instance ID (machine + path hash, never persisted)
INSTANCE_NAME=$(hostname -s 2>/dev/null || echo unknown)
PATH_HASH=$(printf "%s" "$PROJECT_ROOT" | git hash-object --stdin | head -c 8)
INSTANCE_ID="${INSTANCE_NAME}-${PATH_HASH}"

# Install commit-msg hook (idempotent)
HOOK_PATH=".git/hooks/commit-msg"
if [ ! -f "$HOOK_PATH" ] || ! grep -q "agent-trailer-injector" "$HOOK_PATH" 2>/dev/null; then
    cat > "$HOOK_PATH" <<HOOK_EOF
#!/usr/bin/env bash
# agent-trailer-injector
MSG_FILE="\$1"
HANDLE="$HANDLE"
INSTANCE_ID="$INSTANCE_ID"
grep -q "Co-Authored-By: Claude Code" "\$MSG_FILE" || \\
    printf "\nCo-Authored-By: Claude Code [\${HANDLE}] <noreply@anthropic.com>\n" >> "\$MSG_FILE"
grep -q "Agent-Instance:" "\$MSG_FILE" || \\
    printf "Agent-Instance: \${INSTANCE_ID}\n" >> "\$MSG_FILE"
HOOK_EOF
    chmod +x "$HOOK_PATH"
fi

# Print summary (consumed by SessionStart UI)
echo "Agent identity: $HANDLE"
echo "Instance: $INSTANCE_ID"
SS_EOF
chmod +x "$D/.claude/hooks/session-start.sh"

# 3. Run the hook once to install the commit-msg hook
( cd "$D" && bash .claude/hooks/session-start.sh >/dev/null 2>&1 || true )

echo "  Stage 1 patch applied: agent-id, session-start.sh, commit-msg hook installed."

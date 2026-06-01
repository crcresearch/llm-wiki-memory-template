#!/usr/bin/env bash
# Stage 3: SessionStart fetch + auto-pull + incoming-changes report.
# Depends on Stage 1 (extends its SessionStart hook).
#
# Inputs:  SANDBOX env var pointing at the sandbox root.
# Effects:
#   1. Sets up a bare repo at $SANDBOX/wiki-remote.git as the wiki's origin.
#   2. Configures origin + upstream tracking on the local wiki.
#   3. Pushes initial state so origin has the baseline.
#   4. Rewrites session-start.sh with Stage 1 (identity) + Stage 3 (fetch
#      / auto-pull / report) content. Re-runs hook to refresh commit-msg
#      with the current handle.
#
# Idempotent.

set -euo pipefail

D="$SANDBOX/derivative"

# --- Find the wiki dir ---
WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
[ -z "$WIKI_DIR" ] && { echo "  ERROR: no wiki dir in $D/wiki" >&2; exit 1; }

# --- Set up a bare remote (idempotent) ---
# IMPORTANT: init.defaultBranch=master matches the wiki's branch (set in
# init_derivative). Without it, the bare's HEAD points to the system default
# (often 'main'), and `git clone` warns "remote HEAD refers to nonexistent
# ref" and produces an empty working tree, which breaks the side-clone tests.
WIKI_REMOTE="$SANDBOX/wiki-remote.git"
[ -d "$WIKI_REMOTE" ] || git -c init.defaultBranch=master init --bare --quiet "$WIKI_REMOTE"

# Configure origin (handle the "already exists" case)
if git -C "$WIKI_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$WIKI_DIR" remote set-url origin "$WIKI_REMOTE"
else
    git -C "$WIKI_DIR" remote add origin "$WIKI_REMOTE"
fi

# Push initial state and set upstream tracking. Push may be a no-op if
# already pushed; fine either way.
git -C "$WIKI_DIR" push --quiet -u origin master 2>/dev/null || true

# --- Rewrite session-start.sh with Stage 1 + Stage 3 content ---
cat > "$D/.claude/hooks/session-start.sh" <<'SS_EOF'
#!/usr/bin/env bash
# Stage 1 + Stage 3: agent identity + wiki fetch + auto-pull + report.
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[ -z "$PROJECT_ROOT" ] && exit 0
cd "$PROJECT_ROOT"

# ----- Identity setup ----------------------------------------------------
if [ -f .claude/agent-id ]; then
    HANDLE=$(grep -v '^#' .claude/agent-id | grep -v '^[[:space:]]*$' | head -n1 | tr -d '[:space:]')
else
    HUMAN=$(git config user.email | cut -d@ -f1)
    PROJECT=$(basename "$PROJECT_ROOT")
    HANDLE="claude-${HUMAN}@${PROJECT}"
fi

INSTANCE_NAME=$(hostname -s 2>/dev/null || echo unknown)
PATH_HASH=$(printf "%s" "$PROJECT_ROOT" | git hash-object --stdin | head -c 8)
INSTANCE_ID="${INSTANCE_NAME}-${PATH_HASH}"

HOOK_PATH=".git/hooks/commit-msg"
if [ ! -f "$HOOK_PATH" ] || ! grep -q "agent-trailer-injector" "$HOOK_PATH" 2>/dev/null; then
    cat > "$HOOK_PATH" <<HOOK_EOF
#!/usr/bin/env bash
# agent-trailer-injector
MSG_FILE="\$1"
HANDLE="$HANDLE"
INSTANCE_ID="$INSTANCE_ID"
grep -q "Co-Authored-By: claude-" "\$MSG_FILE" || \\
    printf "\nCo-Authored-By: \${HANDLE} <noreply@anthropic.com>\n" >> "\$MSG_FILE"
grep -q "Agent-Instance:" "\$MSG_FILE" || \\
    printf "Agent-Instance: \${INSTANCE_ID}\n" >> "\$MSG_FILE"
HOOK_EOF
    chmod +x "$HOOK_PATH"
fi

# ----- Wiki fetch + auto-pull + report -----------------------------------
WIKI_DIR=$(find wiki -maxdepth 2 -name "*.wiki" -type d 2>/dev/null | head -n1)
if [ -n "$WIKI_DIR" ] && [ -d "$WIKI_DIR/.git" ]; then
    git -C "$WIKI_DIR" fetch --quiet 2>/dev/null || true
    INCOMING=$(git -C "$WIKI_DIR" log --oneline HEAD..@{u} 2>/dev/null || true)
    if [ -n "$INCOMING" ]; then
        COUNT=$(printf "%s\n" "$INCOMING" | wc -l | tr -d ' ')
        echo "Wiki has $COUNT incoming commit(s) since your last session:"
        printf "%s\n" "$INCOMING" | sed 's/^/  /'
        if git -C "$WIKI_DIR" pull --ff-only --quiet 2>/dev/null; then
            echo "Auto-pulled. Local wiki now at remote HEAD."
            echo "Consider reading the new pages before continuing related work."
        else
            echo "Could not auto-pull (not fast-forward). Manual resolution needed:"
            echo "  git -C $WIKI_DIR pull --rebase"
        fi
    else
        echo "Wiki is up to date with origin."
    fi
fi

# ----- Identity summary --------------------------------------------------
echo "Agent identity: $HANDLE"
echo "Instance: $INSTANCE_ID"
SS_EOF
chmod +x "$D/.claude/hooks/session-start.sh"

# Re-run to refresh commit-msg hook with the current handle
( cd "$D" && bash .claude/hooks/session-start.sh >/dev/null 2>&1 || true )

echo "  Stage 3 patch applied: bare remote at $WIKI_REMOTE, SessionStart now fetches + auto-pulls."

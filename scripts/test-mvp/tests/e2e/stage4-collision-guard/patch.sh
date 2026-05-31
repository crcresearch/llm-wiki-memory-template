#!/usr/bin/env bash
# Stage 4: pre-push collision guard.
# Depends on Stage 1 (for hook installation pattern). In the test harness
# also leverages Stage 3's bare remote; idempotent remote setup here means
# Stage 4 can also run standalone after Stage 1 if needed.
#
# Inputs:  SANDBOX env var pointing at the sandbox root.
# Effects:
#   1. Ensures bare remote exists at $SANDBOX/wiki-remote.git (idempotent).
#   2. Rewrites session-start.sh with Stage 1 + Stage 3 + Stage 4 content.
#   3. Runs the hook so the pre-push hook gets installed in the wiki repo.
#
# Idempotent.

set -euo pipefail

D="$SANDBOX/derivative"

WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
[ -z "$WIKI_DIR" ] && { echo "  ERROR: no wiki dir in $D/wiki" >&2; exit 1; }

# --- Idempotent remote setup (in case Stage 3 hasn't run) ---
WIKI_REMOTE="$SANDBOX/wiki-remote.git"
[ -d "$WIKI_REMOTE" ] || git init --bare --initial-branch=master --quiet "$WIKI_REMOTE"
if git -C "$WIKI_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$WIKI_DIR" remote set-url origin "$WIKI_REMOTE"
else
    git -C "$WIKI_DIR" remote add origin "$WIKI_REMOTE"
fi
git -C "$WIKI_DIR" push --quiet -u origin master 2>/dev/null || true

# --- Rewrite session-start.sh with Stage 1 + Stage 3 + Stage 4 content ---
cat > "$D/.claude/hooks/session-start.sh" <<'SS_EOF'
#!/usr/bin/env bash
# Stage 1 + Stage 3 + Stage 4: identity + wiki fetch + auto-pull + pre-push.
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

    # ----- Install pre-push collision guard in the wiki repo ------------
    WIKI_HOOK="$WIKI_DIR/.git/hooks/pre-push"
    if [ ! -f "$WIKI_HOOK" ] || ! grep -q "wiki-push-collision-guard" "$WIKI_HOOK" 2>/dev/null; then
        cat > "$WIKI_HOOK" <<'PP_EOF'
#!/usr/bin/env bash
# wiki-push-collision-guard
# Fetch, attempt rebase of local commits on top of remote, push if clean,
# abort with user-readable message if rebase fails.
set -e
git fetch origin --quiet
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
[ -z "$REMOTE" ] || [ "$LOCAL" = "$REMOTE" ] && exit 0

BEHIND=$(git rev-list HEAD..@{u} --count)
[ "$BEHIND" -eq 0 ] && exit 0   # purely ahead, safe to push

echo "Wiki has $BEHIND incoming commit(s); rebasing local commits on top..." >&2
if git rebase @{u} >&2; then
    # IMPORTANT: git push resolves the refspec BEFORE pre-push runs. Even
    # though we rebased successfully, git push will still try to send the
    # original (pre-rebase) SHA and the remote will reject it with
    # "fetch first" / "non-fast-forward". So we abort the push and tell
    # the user to re-run; the rebase work persists.
    cat >&2 <<MSG

Rebase clean. Local commits are now on top of the incoming commits.
The push has been aborted because git push uses refs from before the
hook ran. Re-run 'git push' to publish (next time will be a clean
fast-forward).
MSG
    exit 1
fi

CONFLICTS=$(git diff --name-only --diff-filter=U)
git rebase --abort
cat >&2 <<MSG

BLOCKED: push aborted -- local commits conflict with incoming wiki edits.

Conflicting files:
$CONFLICTS

Manual resolution needed:
  1. cd $(pwd)
  2. git pull --rebase
  3. Resolve conflicts in the files above
  4. git rebase --continue
  5. git push

MSG
exit 1
PP_EOF
        chmod +x "$WIKI_HOOK"
    fi
fi

# ----- Identity summary --------------------------------------------------
echo "Agent identity: $HANDLE"
echo "Instance: $INSTANCE_ID"
SS_EOF
chmod +x "$D/.claude/hooks/session-start.sh"

# Run the hook so the pre-push gets installed (and commit-msg refreshed)
( cd "$D" && bash .claude/hooks/session-start.sh >/dev/null 2>&1 || true )

echo "  Stage 4 patch applied: pre-push collision guard installed in wiki repo."

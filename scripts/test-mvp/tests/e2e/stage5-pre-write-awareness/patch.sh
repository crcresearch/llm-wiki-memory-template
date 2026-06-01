#!/usr/bin/env bash
# Stage 5: mid-session pre-write awareness.
# Installs a PreToolUse hook that fires on Edit/Write of wiki files,
# fetches the wiki, and surfaces incoming changes (non-blocking).
# Plus a /wiki-status slash command for on-demand checks.
#
# Independent of Stages 1, 3, 4. Idempotent remote setup so this stage
# can run standalone after Stage 0 (the hook needs a remote to fetch
# from, otherwise it silently no-ops).

set -euo pipefail

D="$SANDBOX/derivative"

WIKI_DIR=$(find "$D/wiki" -maxdepth 2 -name "*.wiki" -type d | head -n1)
[ -z "$WIKI_DIR" ] && { echo "  ERROR: no wiki dir in $D/wiki" >&2; exit 1; }

# --- Idempotent remote setup (in case earlier stages haven't run) ---
WIKI_REMOTE="$SANDBOX/wiki-remote.git"
[ -d "$WIKI_REMOTE" ] || git -c init.defaultBranch=master init --bare --quiet "$WIKI_REMOTE"
if git -C "$WIKI_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$WIKI_DIR" remote set-url origin "$WIKI_REMOTE"
else
    git -C "$WIKI_DIR" remote add origin "$WIKI_REMOTE"
fi
git -C "$WIKI_DIR" push --quiet -u origin master 2>/dev/null || true

# --- Install pre-write-fetch.sh ---
mkdir -p "$D/.claude/hooks"
cat > "$D/.claude/hooks/pre-write-fetch.sh" <<'PWF_EOF'
#!/usr/bin/env bash
# PreToolUse hook for Edit / Write on wiki files.
# Fetches the wiki and surfaces incoming changes before the write proceeds.
# Non-blocking: always exit 0; the write happens either way. The agent
# reads the printed report and decides whether to read the changed pages.
#
# Input: JSON on stdin per Claude Code hook spec.
# Requires: jq.

INPUT=$(cat)

# jq required; if missing, silently no-op
command -v jq >/dev/null 2>&1 || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Find the wiki directory from the file's directory (the agent's CWD may
# differ from the project being edited). Canonicalize FILE_PATH to the
# physical form so the path-prefix match below works through symlinks
# (e.g. macOS resolves /var/folders/... to /private/var/folders/...).
DIR_OF_FILE="$(dirname "$FILE_PATH")"
[ ! -d "$DIR_OF_FILE" ] && exit 0
DIR_CANON=$(cd "$DIR_OF_FILE" 2>/dev/null && pwd -P || echo "$DIR_OF_FILE")
FILE_PATH="$DIR_CANON/$(basename "$FILE_PATH")"

TOPLEVEL=$(git -C "$DIR_CANON" rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$TOPLEVEL" ] && exit 0

# If the toplevel itself ends in .wiki, the file is inside the wiki repo
# directly. Otherwise the toplevel is the derivative repo and the wiki is
# under wiki/*.wiki/.
case "$TOPLEVEL" in
    *.wiki)
        WIKI_DIR="$TOPLEVEL"
        ;;
    *)
        WIKI_DIR=$(find "$TOPLEVEL/wiki" -maxdepth 2 -name "*.wiki" -type d 2>/dev/null | head -n1)
        ;;
esac
[ -z "$WIKI_DIR" ] && exit 0

# Path filter: only fire when the target file is inside the wiki dir
case "$FILE_PATH" in
    "$WIKI_DIR"/*) ;;
    *) exit 0 ;;
esac

# Fetch and report incoming changes
git -C "$WIKI_DIR" fetch --quiet 2>/dev/null || exit 0
INCOMING=$(git -C "$WIKI_DIR" log --name-only --pretty=format:"  %h by %an: %s" HEAD..@{u} 2>/dev/null | head -30)
[ -z "$INCOMING" ] && exit 0

echo "Wiki has incoming changes since last fetch:"
printf "%s\n" "$INCOMING"
echo ""
echo "Consider reading the changed pages before writing -- collaborator's work may inform yours."
echo "(Auto-pull: git -C $WIKI_DIR pull --ff-only)"
exit 0  # always non-blocking, even after printing
PWF_EOF
chmod +x "$D/.claude/hooks/pre-write-fetch.sh"

# --- Install /wiki-status slash command ---
mkdir -p "$D/.claude/commands"
cat > "$D/.claude/commands/wiki-status.md" <<'WS_EOF'
---
description: Fetch the wiki and report any incoming changes since last fetch.
---

Run the following sequence and report the results:

1. Find the wiki directory: `find wiki -maxdepth 2 -name "*.wiki" -type d | head -n1`
2. Fetch: `git -C <wiki-dir> fetch --quiet`
3. List incoming commits with affected page names: `git -C <wiki-dir> log --name-only --pretty=format:"%h by %an: %s" HEAD..@{u} | head -30`
4. If anything came in, list the changed pages by author and offer to pull (`git -C <wiki-dir> pull --ff-only`).
5. If nothing came in, report "Wiki up to date."
WS_EOF

echo "  Stage 5 patch applied: pre-write-fetch.sh + /wiki-status command installed."

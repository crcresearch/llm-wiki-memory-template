#!/usr/bin/env bash
# Patch: stage a fixture for the init-wiki naming / push-branch test.
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/init-wiki-naming/ with:
#   gitconfig  a sandbox global git config: identity (so the wiki repo's
#              commit succeeds) and init.defaultBranch=trunk (so the wiki
#              repo init's onto a NON-default branch). The F5 assertion uses
#              this to tell a detected branch apart from a hardcoded 'master'.
#   clonedir/  git repo whose basename ('clonedir') deliberately differs from
#              its origin repo name ('widget'), proving init-wiki derives the
#              namespace from origin, not the clone directory (F1).
#
# Hermetic: create mode needs no network (init-wiki inits the wiki locally).

set -uo pipefail

STAGE="$SANDBOX/init-wiki-naming"
mkdir -p "$STAGE"

GITCONFIG="$STAGE/gitconfig"
cat > "$GITCONFIG" <<'EOF'
[user]
	name = initwiki test
	email = initwiki-test@example.test
[init]
	defaultBranch = trunk
EOF

# init reads init.defaultBranch from the global config we pin here.
GIT_CONFIG_GLOBAL="$GITCONFIG" GIT_CONFIG_SYSTEM=/dev/null git init -q "$STAGE/clonedir"
git -C "$STAGE/clonedir" remote add origin "https://github.com/acme/widget.git"

echo "  init-wiki-naming patch applied: fixture at $STAGE"

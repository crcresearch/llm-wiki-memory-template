#!/usr/bin/env bash
# Patch: fixtures for the template sync scripts (update-from-template.sh,
# check-template-version.sh) migrated onto the shared library (chunk 04).
#
# Inputs:  SANDBOX env var (from run.sh).
# Effects: creates $SANDBOX/template-scripts/ with:
#   gitconfig        sandbox identity + init.defaultBranch=main
#   template-main/   a stand-in template repo, default branch 'main', holding
#                    one substituted file (.claude/commands/wiki-experiment.md
#                    with a literal {{REPO_NAME}})
#   template-trunk/  same content, default branch 'trunk' (NOT main), so the
#                    scripts must DETECT the branch rather than assume main (F5)
#   wrong-remote/    an unrelated repo, used to trip the remote guard (F6)
#   up-clone/        project whose basename differs from its wiki name (widget);
#                    run update against template-main (F1/F2 substitution, F12)
#   br-clone/        project pointed at template-trunk (F5)
#   gd-clone/        project with a pre-existing 'template' remote -> wrong-remote
#                    (F6 guard)
#   ck-clone/        project whose wiki is 'gizmo'; run check-template-version
#                    (F1/F2 name discovery in the second script)
#
# Hermetic: all "remotes" are local paths, contacted over the local transport.

set -uo pipefail

STAGE="$SANDBOX/template-scripts"
mkdir -p "$STAGE"

GITCFG="$STAGE/gitconfig"
cat > "$GITCFG" <<'EOF'
[user]
	name = tmpl test
	email = tmpl-test@example.test
[init]
	defaultBranch = main
EOF

# git with the sandbox-pinned global config (so commits succeed and the default
# branch is deterministic regardless of the host's git config).
g() { GIT_CONFIG_GLOBAL="$GITCFG" GIT_CONFIG_SYSTEM=/dev/null git "$@"; }

# Seed a template-content repo at $1 on branch $2 with the one file the sync
# scripts will substitute.
_mk_template() {
    local dir="$1" branch="$2"
    g init -q "$dir"
    g -C "$dir" symbolic-ref HEAD "refs/heads/$branch"
    mkdir -p "$dir/.claude/commands"
    printf 'command for {{REPO_NAME}}\n' > "$dir/.claude/commands/wiki-experiment.md"
    g -C "$dir" add -A
    g -C "$dir" commit -q -m "template content on $branch"
}

# A project fixture: git repo at $1, with an on-disk wiki named $2 and an
# active .claude/ overlay (so the CLAUDE_FILES are in the sync list), plus a
# stale local copy of the substituted file.
_mk_project() {
    local dir="$1" wiki="$2"
    g init -q "$dir"
    mkdir -p "$dir/wiki/$wiki.wiki"
    : > "$dir/wiki/$wiki.wiki/SCHEMA_$wiki.md"
    mkdir -p "$dir/.claude/commands"
    printf 'stale local content\n' > "$dir/.claude/commands/wiki-experiment.md"
}

_mk_template "$STAGE/template-main"  main
_mk_template "$STAGE/template-trunk" trunk

# wrong-remote: unrelated repo for the guard test.
g init -q "$STAGE/wrong-remote"
printf 'unrelated\n' > "$STAGE/wrong-remote/README.md"
g -C "$STAGE/wrong-remote" add -A
g -C "$STAGE/wrong-remote" commit -q -m "unrelated repo"

_mk_project "$STAGE/up-clone" widget
_mk_project "$STAGE/br-clone" widget
_mk_project "$STAGE/gd-clone" widget
_mk_project "$STAGE/ck-clone" gizmo

# gd-clone already has a 'template' remote pointing at the WRONG repo; the
# guard must reject it rather than fetch (F6).
g -C "$STAGE/gd-clone" remote add template "$STAGE/wrong-remote"

echo "  template-scripts patch applied: fixtures at $STAGE"

#!/usr/bin/env bash
#
# instantiate.sh — first-use bootstrap for a project created from llm-wiki-template.
#
# Usage:
#   ./scripts/instantiate.sh "<Project Name>" [--agent=<x>] [--description="..."] [--github-wiki]
#
# Positional:
#   <Project Name>   Human-readable project name (e.g. "Data Platform Notes").
#                    Substituted for {{PROJECT_NAME}} in CLAUDE.md.template.
#
# Flags:
#   --agent=<x>      Agent overlay to activate. One of:
#                      none         minimal: only llm-wiki core (for OpenCode, Pi, etc.)
#                      claude-code  install Claude Code overlay (default)
#                      cursor       install Cursor overlay
#                      all          install both Claude Code and Cursor overlays
#   --description=   One-sentence description of the project. Substituted for
#                    {{DESCRIPTION}} in CLAUDE.md.template. If omitted, CLAUDE.md
#                    is left with a placeholder you can edit by hand.
#   --github-wiki    Use the GitHub Wiki of the project's main repo as the
#                    wiki sub-repo backend (instead of init'ing a local-only
#                    wiki).
#
#                    IMPORTANT: GitHub typically requires the first Wiki
#                    page to be created through the UI before
#                    <repo>.wiki.git materializes as a clonable/pushable
#                    repository. This script attempts a direct push of a
#                    seed Home.md anyway (it costs nothing if it fails)
#                    and falls back with explicit instructions to open
#                    the UI, create one page, and re-run.
#
#                    Requires `origin` to be set on the main repo, an SSH
#                    key registered for github.com, and `gh` (optional,
#                    defensive) for the has_wiki=true PATCH.
#
# Idempotent failure mode: if CLAUDE.md already exists at the repo root, this
# script exits immediately. Templates are one-shot.
#

set -euo pipefail

# --- Parse arguments ---
PROJECT_NAME=""
AGENT="claude-code"
DESCRIPTION=""
GITHUB_WIKI=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --agent=*)        AGENT="${1#*=}"; shift ;;
        --description=*)  DESCRIPTION="${1#*=}"; shift ;;
        --github-wiki)    GITHUB_WIKI=true; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        --*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            if [[ -z "$PROJECT_NAME" ]]; then
                PROJECT_NAME="$1"
            else
                echo "Unexpected positional arg: $1" >&2; exit 1
            fi
            shift ;;
    esac
done

if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: <Project Name> is required (positional arg)." >&2
    echo "Run with --help for usage." >&2
    exit 1
fi

case "$AGENT" in
    none|claude-code|cursor|all) ;;
    *) echo "Error: --agent must be one of: none, claude-code, cursor, all" >&2; exit 1 ;;
esac

# --- Detect project layout ---
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REPO_NAME=$(basename "$REPO_ROOT")
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
CLAUDE_MD_TEMPLATE="$REPO_ROOT/CLAUDE.md.template"

if [[ -f "$CLAUDE_MD" ]]; then
    echo "Error: CLAUDE.md already exists at $CLAUDE_MD" >&2
    echo "       instantiate.sh is for first-use only. Either delete CLAUDE.md" >&2
    echo "       to re-run, or use scripts/update-from-template.sh for updates." >&2
    exit 1
fi

if [[ ! -f "$CLAUDE_MD_TEMPLATE" ]]; then
    echo "Error: $CLAUDE_MD_TEMPLATE not found. Was the template properly cloned?" >&2
    exit 1
fi

# --- Build the agent note that goes in CLAUDE.md ---
# This is the line in CLAUDE.md.template marked {{AGENT_NOTE}}.
# Each agent gets a slightly different sentence so the user knows which entry
# points are active.

case "$AGENT" in
    none)
        AGENT_NOTE=""
        ;;
    claude-code)
        AGENT_NOTE="Claude Code users have project-level slash commands available for explicit invocation: \`/wiki-experiment\`, \`/wiki-source\`, \`/wiki-lint\`. See \`.claude/commands/\`. The project also ships the same procedures as model-side skills at \`.claude/skills/\` (referenced by the slash commands). The slash commands are a safety net: the proactive behavior described above is the default, the slash commands exist for cases where the user wants to force the action explicitly."
        ;;
    cursor)
        AGENT_NOTE="Cursor users have project-level rules at \`.cursor/rules/wiki-*.mdc\`. The \`wiki-as-memory\` rule is alwaysApply (injected into every prompt); the three operation rules (\`wiki-experiment\`, \`wiki-source\`, \`wiki-lint\`) are Agent Requested and can be invoked explicitly with \`@wiki-experiment\`, \`@wiki-source\`, \`@wiki-lint\`. They are a safety net: the proactive behavior described above is the default."
        ;;
    all)
        AGENT_NOTE="Claude Code users have slash commands at \`.claude/commands/\` (\`/wiki-experiment\`, \`/wiki-source\`, \`/wiki-lint\`) and model-side skills at \`.claude/skills/\`. Cursor users have rules at \`.cursor/rules/wiki-*.mdc\` (\`@wiki-experiment\`, \`@wiki-source\`, \`@wiki-lint\`). Both are safety nets for the proactive default behavior described above."
        ;;
esac

# --- Substitute placeholders in CLAUDE.md.template -> CLAUDE.md ---
TMP=$(mktemp)
sed \
    -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
    -e "s|{{REPO_NAME}}|$REPO_NAME|g" \
    -e "s|{{DESCRIPTION}}|${DESCRIPTION:-<one-sentence description, edit me>}|g" \
    "$CLAUDE_MD_TEMPLATE" > "$TMP"

# Replace the {{AGENT_NOTE}} line with the agent-specific block (or remove if none).
# Using python for the multi-line substitution because sed across newlines is fragile.
python3 - "$TMP" "$AGENT_NOTE" "$CLAUDE_MD" <<'PYEOF'
import sys, pathlib
src, note, dst = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(src).read_text()
text = text.replace("{{AGENT_NOTE}}", note)
# Trim trailing blank lines if the note was empty.
text = text.rstrip() + "\n"
pathlib.Path(dst).write_text(text)
PYEOF
rm -f "$TMP"
rm -f "$CLAUDE_MD_TEMPLATE"

echo "Wrote CLAUDE.md (PROJECT_NAME=$PROJECT_NAME, REPO_NAME=$REPO_NAME, agent=$AGENT)"

# --- Bootstrap the wiki ---
if [[ -d "$REPO_ROOT/wiki/${REPO_NAME}.wiki" ]]; then
    echo "Wiki sub-repo already present at wiki/${REPO_NAME}.wiki/, skipping init-wiki.sh"
else
    if $GITHUB_WIKI; then
        # --- Pre-step: ensure the GitHub Wiki is initialized ---
        # The GitHub Wiki at <repo>.wiki.git is materialized only after a first
        # page is created. Without that, `git clone <repo>.wiki.git` (which
        # init-wiki.sh --github relies on) fails. To avoid forcing the user
        # through the GitHub UI, this block:
        #   1. Derives <repo>.wiki.git from the main repo's origin URL.
        #   2. Checks if the wiki remote is already initialized.
        #   3. If not, pushes a one-commit seed (Home.md) directly to it.
        #      init-wiki.sh will then patch its namespaced files on top.

        ORIGIN_URL=$(cd "$REPO_ROOT" && git remote get-url origin 2>/dev/null || true)
        if [[ -z "$ORIGIN_URL" ]]; then
            echo "Error: --github-wiki requires a git remote 'origin' on the main repo." >&2
            echo "       Push the project repo to GitHub first, then re-run." >&2
            exit 1
        fi
        case "$ORIGIN_URL" in
            *.git) WIKI_REMOTE_URL="${ORIGIN_URL%.git}.wiki.git" ;;
            *)     WIKI_REMOTE_URL="${ORIGIN_URL}.wiki.git" ;;
        esac

        # For the seed push, prefer SSH over HTTPS. HTTPS push to GitHub
        # requires a stored credential (PAT or credential helper); SSH uses
        # the key the user already has registered (and that gh requires
        # for the main repo). Convert https://github.com/... -> git@github.com:...
        case "$WIKI_REMOTE_URL" in
            https://github.com/*)
                WIKI_PUSH_URL="git@github.com:${WIKI_REMOTE_URL#https://github.com/}"
                ;;
            *)
                WIKI_PUSH_URL="$WIKI_REMOTE_URL"
                ;;
        esac

        if ! git ls-remote "$WIKI_PUSH_URL" >/dev/null 2>&1; then
            echo "GitHub Wiki not initialized yet at $WIKI_REMOTE_URL"
            echo "Bootstrapping with a seed Home.md via direct push (over SSH) ..."

            # Best-effort: ensure has_wiki=true on the main repo (idempotent;
            # default is already true, so this is just defensive).
            # Extract OWNER/REPO from ORIGIN_URL with bash parameter expansion
            # (portable across GNU and BSD sed; sed -E with +? was not).
            if command -v gh >/dev/null 2>&1; then
                REPO_SLUG="${ORIGIN_URL%.git}"
                REPO_SLUG="${REPO_SLUG#git@github.com:}"
                REPO_SLUG="${REPO_SLUG#https://github.com/}"
                REPO_SLUG="${REPO_SLUG#http://github.com/}"
                gh api "repos/$REPO_SLUG" -X PATCH -F has_wiki=true >/dev/null 2>&1 || true
            fi

            # Note: `set -e` is disabled by bash inside the (subshell) of an
            # `if (...); then`, so we use a `&&` chain to short-circuit on
            # any failure. The chain's exit code is what `if` evaluates,
            # which gives us correct error propagation.
            #
            # Also note: GitHub typically REQUIRES that the first Wiki page
            # be created through the UI before <repo>.wiki.git materializes.
            # The push below may therefore fail with "Repository not found"
            # even with valid auth and has_wiki=true. That is not a bug in
            # this script — it is a GitHub Wiki architecture constraint.
            # The fallback message below points the user at the UI URL.
            if (
                TMP=$(mktemp -d) \
                && cd "$TMP" \
                && git init -b master -q \
                && printf '# Home\n\nBootstrapped by llm-wiki-template/scripts/instantiate.sh.\n' > Home.md \
                && git add Home.md \
                && git \
                    -c user.email=instantiate@llm-wiki-template \
                    -c user.name="instantiate.sh" \
                    commit -m "Initialize wiki" -q \
                && git push -q "$WIKI_PUSH_URL" master:master \
                && cd / \
                && rm -rf "$TMP"
            ); then
                echo "Wiki bootstrapped at $WIKI_PUSH_URL"
            else
                # URL the user can open to bootstrap manually.
                # Bash parameter expansion (portable; avoids sed -E variants).
                WIKI_UI_URL="${ORIGIN_URL%.git}"
                WIKI_UI_URL="${WIKI_UI_URL/git@github.com:/https://github.com/}"
                WIKI_UI_URL="${WIKI_UI_URL}/wiki"
                echo "" >&2
                echo "Wiki bootstrap via direct push failed." >&2
                echo "This is the most common outcome on the first --github-wiki" >&2
                echo "run for a project: GitHub requires the first Wiki page to be" >&2
                echo "created through the UI before <repo>.wiki.git becomes a" >&2
                echo "clonable/pushable repository. Until then, push returns 404." >&2
                echo "" >&2
                echo "Workaround:" >&2
                echo "  1. Open $WIKI_UI_URL in a browser." >&2
                echo "  2. Click \"Create the first page\", title \"Home\", any content, save." >&2
                echo "  3. Re-run: ./scripts/instantiate.sh \"$PROJECT_NAME\" --agent=$AGENT --github-wiki" >&2
                echo "     (delete CLAUDE.md first if it was generated by the partial run)" >&2
                echo "" >&2
                echo "Or, to skip GitHub Wiki entirely and use a local-only wiki:" >&2
                echo "  rm CLAUDE.md && ./scripts/instantiate.sh \"$PROJECT_NAME\" --agent=$AGENT" >&2
                exit 1
            fi
        fi

        "$REPO_ROOT/wiki/init-wiki.sh" --github
    else
        "$REPO_ROOT/wiki/init-wiki.sh"
    fi
fi

# --- Strip the Knowledge Graph subsection from CLAUDE.md if this project
#     does not ship the scripts/kg/ pipeline that the subsection references.
#     init-wiki.sh appends "### Knowledge Graph" pointing at scripts/kg/build-graph.sh
#     and a Fuseki SPARQL endpoint; on a fresh template-derived project those
#     don't exist, so the subsection is a dead reference.
if [[ ! -d "$REPO_ROOT/scripts/kg" ]] && grep -qF "### Knowledge Graph" "$CLAUDE_MD"; then
    python3 - "$CLAUDE_MD" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
text = p.read_text()
# Match "### Knowledge Graph" up to the next "##" heading or EOF.
# (?ms) = multiline + dotall. The next-heading lookahead protects sibling sections.
pattern = re.compile(r"(?ms)^### Knowledge Graph\b.*?(?=^## |\Z)")
new = pattern.sub("", text)
# Collapse the trailing blank lines left behind by the removal.
new = new.rstrip() + "\n"
p.write_text(new)
PYEOF
    echo "Stripped Knowledge Graph subsection from CLAUDE.md (no scripts/kg/ in this project)"
fi

# --- Activate the chosen agent overlay(s) and prune the others ---
keep_claude_code=false
keep_cursor=false
case "$AGENT" in
    none)         ;;
    claude-code)  keep_claude_code=true ;;
    cursor)       keep_cursor=true ;;
    all)          keep_claude_code=true; keep_cursor=true ;;
esac

# Claude Code
if $keep_claude_code; then
    # Substitute {{REPO_NAME}} in shipped .claude/ files (one-shot at instantiate).
    for f in "$REPO_ROOT/.claude/commands/"wiki-*.md "$REPO_ROOT/.claude/skills/"wiki-*.md; do
        [[ -f "$f" ]] || continue
        sed -i.bak "s|{{REPO_NAME}}|$REPO_NAME|g" "$f"
        rm -f "${f}.bak"
    done
    # settings.json.template -> settings.json with substitution
    if [[ -f "$REPO_ROOT/.claude/settings.json.template" ]]; then
        sed "s|{{REPO_NAME}}|$REPO_NAME|g" "$REPO_ROOT/.claude/settings.json.template" \
            > "$REPO_ROOT/.claude/settings.json"
        rm -f "$REPO_ROOT/.claude/settings.json.template"
    fi
    # Run the overlay's setup.sh (base mode; user can re-run with --hook/--seed-memory)
    "$REPO_ROOT/wiki/agents/claude-code/setup.sh"
else
    rm -rf "$REPO_ROOT/.claude"
    rm -rf "$REPO_ROOT/wiki/agents/claude-code"
fi

# Cursor
if $keep_cursor; then
    # Substitute {{REPO_NAME}} in shipped .cursor/ files
    for f in "$REPO_ROOT/.cursor/rules/"wiki-*.mdc; do
        [[ -f "$f" ]] || continue
        sed -i.bak "s|{{REPO_NAME}}|$REPO_NAME|g" "$f"
        rm -f "${f}.bak"
    done
    # Run the overlay's setup.sh
    "$REPO_ROOT/wiki/agents/cursor/setup.sh"
else
    rm -rf "$REPO_ROOT/.cursor"
    rm -f "$REPO_ROOT/.cursorrules.template"
    rm -rf "$REPO_ROOT/wiki/agents/cursor"
fi

# --- Final checklist ---
echo ""
echo "================ Instantiation complete ================"
echo "Project:  $PROJECT_NAME"
echo "Repo:     $REPO_NAME"
echo "Agent:    $AGENT"
echo "--------------------------------------------------------"
echo "Next steps:"
echo "  1. Edit CLAUDE.md: fill the description and any project-specific conventions."
echo "  2. Edit README.md: replace the template's README with one for THIS project."
case "$AGENT" in
    claude-code|all)
        echo "  3. (Optional) Add the SessionStart hook and personal memory seed:"
        echo "       ./wiki/agents/claude-code/setup.sh --all"
        ;;
    cursor)
        echo "  3. (Optional) Add the legacy .cursorrules fallback:"
        echo "       ./wiki/agents/cursor/setup.sh --legacy"
        ;;
esac
echo "  4. Stage and commit the generated files:"
echo "       git add -A && git commit -m \"chore: instantiate from llm-wiki-template\""
echo "  5. Open your AI assistant in the project root and start working."
echo "========================================================"

# --- Self-delete (one-shot pattern) ---
# instantiate.sh exists only to bootstrap a new project. After a successful
# run, remove it from the project so:
#   1. It cannot be re-executed accidentally (CLAUDE.md would already exist,
#      and the guard at the top of this script would refuse anyway, but the
#      cleaner outcome is "the file is not there").
#   2. update-from-template.sh and check-template-version.sh do not have to
#      special-case its presence (it is excluded from their sync lists).
# The canonical version of this script lives in the template repo. To
# re-instantiate, clone the template again.
echo ""
echo "(instantiate.sh is one-shot. Removing it from the project."
echo " The canonical version lives in the template repo.)"
rm -f "$0"

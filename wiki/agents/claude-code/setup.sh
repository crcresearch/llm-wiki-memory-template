#!/usr/bin/env bash
#
# setup.sh — Claude Code overlay on top of an llm-wiki project.
#
# This script is the Claude-Code-specific layer of the llm-wiki pattern.
# It is intentionally separate from wiki/init-wiki.sh, which stays
# agent-agnostic. Other agents (Codex, Cursor, etc.) would live in
# parallel directories under wiki/agents/.
#
# Usage:
#   ./wiki/agents/claude-code/setup.sh                       # base: CLAUDE.md + verify commands & skills
#   ./wiki/agents/claude-code/setup.sh --hook                # + SessionStart hook
#   ./wiki/agents/claude-code/setup.sh --seed-memory         # + personal memory seed
#   ./wiki/agents/claude-code/setup.sh --posttooluse-hook    # + PostToolUse advisory hook
#                                                            #   (fires after Write; nudges
#                                                            #    agent through verification-gate
#                                                            #    criteria; advisory, does not block)
#   ./wiki/agents/claude-code/setup.sh --all                 # everything
#
# Idempotent: safe to re-run. Auto-detects what is already in place.
#
# Required prerequisites:
#   - The wiki must already exist (wiki/<repo>.wiki/SCHEMA_<repo>.md).
#     If missing, run wiki/init-wiki.sh first.
#   - .claude/commands/wiki-{experiment,source,lint}.md and
#     .claude/skills/wiki-{experiment,source,lint}.md should be committed
#     in the repo (they ship with this overlay).
#
# What it does:
#   Base mode:
#     1. Verifies the wiki is present (else prints how to run init-wiki.sh).
#     2. Patches CLAUDE.md with the "Wiki maintenance behavior" subsection,
#        if not already present (idempotent marker check).
#     3a. Reports presence/absence of .claude/commands/wiki-*.md (slash
#         commands invoked via /wiki-experiment, /wiki-source, /wiki-lint).
#     3b. Reports presence/absence of .claude/skills/wiki-*.md (model-side
#         procedures referenced by the slash commands).
#
#   --hook:
#     4. Installs .claude/hooks/session-start.sh from the template,
#        substituting ${REPO_NAME}.
#     5. Registers the hook in .claude/settings.json (creating or updating
#        the file conservatively).
#
#   --seed-memory:
#     6. Computes the per-user Claude Code memory directory for this repo
#        (~/.claude/projects/<encoded-path>/memory/).
#     7. Writes wiki-as-project-memory.md from the template, with ${REPO_NAME}
#        substituted. Will not overwrite an existing file with different
#        content (prompts user instead).
#     8. Creates or appends to MEMORY.md index.
#
# Does not commit anything. Tells the user what to stage.
# Does not push anything.
#

set -euo pipefail

# --- Parse arguments ---
WITH_HOOK=false
WITH_SEED_MEMORY=false
WITH_POSTTOOLUSE_HOOK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --hook) WITH_HOOK=true; shift ;;
        --seed-memory) WITH_SEED_MEMORY=true; shift ;;
        --posttooluse-hook) WITH_POSTTOOLUSE_HOOK=true; shift ;;
        --all) WITH_HOOK=true; WITH_SEED_MEMORY=true; WITH_POSTTOOLUSE_HOOK=true; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Detect project layout ---
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REPO_NAME=$(basename "$REPO_ROOT")
WIKI_DIR="$REPO_ROOT/wiki/${REPO_NAME}.wiki"
SCHEMA_FILE="$WIKI_DIR/SCHEMA_${REPO_NAME}.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

OVERLAY_DIR="$REPO_ROOT/wiki/agents/claude-code"
TEMPLATES_DIR="$OVERLAY_DIR/templates"
COMMANDS_DIR="$REPO_ROOT/.claude/commands"
SKILLS_DIR="$REPO_ROOT/.claude/skills"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"

REPORT=()

# --- Step 1: verify wiki present ---
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "ERROR: wiki not found at $WIKI_DIR" >&2
    echo "       (expected $SCHEMA_FILE)" >&2
    echo "" >&2
    echo "Run wiki/init-wiki.sh first, then re-run this script." >&2
    exit 1
fi

# --- Step 2: patch CLAUDE.md ---
SNIPPET_FILE="$TEMPLATES_DIR/claude-md-snippet.md"
MARKER="### Wiki maintenance behavior"

if [[ ! -f "$CLAUDE_MD" ]]; then
    echo "WARNING: CLAUDE.md not found at $CLAUDE_MD. Skipping CLAUDE.md patch." >&2
    REPORT+=("CLAUDE.md: not found (skipped)")
elif grep -qF "$MARKER" "$CLAUDE_MD"; then
    REPORT+=("CLAUDE.md: 'Wiki maintenance behavior' already present (skipped)")
else
    # Inject snippet before "### Knowledge Graph" if present,
    # else append to the end of the file.
    SNIPPET_BODY=$(grep -v '^<!--' "$SNIPPET_FILE" | grep -v '^-->' | sed "s/\${REPO_NAME}/$REPO_NAME/g")

    if grep -qF "### Knowledge Graph" "$CLAUDE_MD"; then
        # Insert before "### Knowledge Graph"
        TMP=$(mktemp)
        awk -v snippet="$SNIPPET_BODY" '
            /^### Knowledge Graph/ && !done {
                print snippet
                print ""
                done = 1
            }
            { print }
        ' "$CLAUDE_MD" > "$TMP"
        mv "$TMP" "$CLAUDE_MD"
        REPORT+=("CLAUDE.md: injected 'Wiki maintenance behavior' before '### Knowledge Graph'")
    else
        printf '\n%s\n' "$SNIPPET_BODY" >> "$CLAUDE_MD"
        REPORT+=("CLAUDE.md: appended 'Wiki maintenance behavior' at end")
    fi
fi

# --- Step 3a: verify slash commands present ---
COMMANDS_MISSING=()
for cmd in wiki-experiment wiki-source wiki-lint; do
    if [[ ! -f "$COMMANDS_DIR/${cmd}.md" ]]; then
        COMMANDS_MISSING+=("$cmd")
    fi
done

if [[ ${#COMMANDS_MISSING[@]} -eq 0 ]]; then
    REPORT+=(".claude/commands/: all three present (wiki-experiment, wiki-source, wiki-lint)")
else
    REPORT+=(".claude/commands/: MISSING — ${COMMANDS_MISSING[*]} (these should be committed in the repo)")
fi

# --- Step 3b: verify model-side skills present ---
SKILLS_MISSING=()
for skill in wiki-experiment wiki-source wiki-lint; do
    if [[ ! -f "$SKILLS_DIR/${skill}.md" ]]; then
        SKILLS_MISSING+=("$skill")
    fi
done

if [[ ${#SKILLS_MISSING[@]} -eq 0 ]]; then
    REPORT+=(".claude/skills/: all three present (wiki-experiment, wiki-source, wiki-lint)")
else
    REPORT+=(".claude/skills/: MISSING — ${SKILLS_MISSING[*]} (these should be committed in the repo)")
fi

# --- Step 4: install SessionStart hook (--hook) ---
if $WITH_HOOK; then
    HOOK_TEMPLATE="$TEMPLATES_DIR/session-start-hook.sh"
    HOOK_DEST="$HOOKS_DIR/session-start.sh"

    mkdir -p "$HOOKS_DIR"

    if [[ -f "$HOOK_DEST" ]]; then
        REPORT+=(".claude/hooks/session-start.sh: already present (not overwritten)")
    else
        sed "s/\${REPO_NAME}/$REPO_NAME/g" "$HOOK_TEMPLATE" > "$HOOK_DEST"
        chmod +x "$HOOK_DEST"
        REPORT+=(".claude/hooks/session-start.sh: installed")
    fi

    # --- Step 5: register hook in settings.json ---
    if [[ ! -f "$SETTINGS_JSON" ]]; then
        cat > "$SETTINGS_JSON" <<JSONEOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": ".claude/hooks/session-start.sh" }
        ]
      }
    ]
  }
}
JSONEOF
        REPORT+=(".claude/settings.json: created with SessionStart hook")
    elif grep -qF '"session-start.sh"' "$SETTINGS_JSON"; then
        REPORT+=(".claude/settings.json: SessionStart hook already registered (skipped)")
    elif command -v jq >/dev/null 2>&1; then
        TMP=$(mktemp)
        jq '. + {
          "hooks": (
            (.hooks // {}) + {
              "SessionStart": (
                (.hooks.SessionStart // []) + [
                  {"hooks": [{"type": "command", "command": ".claude/hooks/session-start.sh"}]}
                ]
              )
            }
          )
        }' "$SETTINGS_JSON" > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
        REPORT+=(".claude/settings.json: merged SessionStart hook (via jq)")
    else
        REPORT+=(".claude/settings.json: exists but SessionStart hook not registered, and jq not found. Manual edit needed: see $HOOK_DEST")
    fi
fi

# --- PostToolUse advisory hook (--posttooluse-hook) ---
# Fires after every Write tool use. If the write target is under wiki/<repo>.wiki/,
# the prompt nudges the agent to verify corpus tagging, projection marking,
# back-references, and log/index updates per wiki/agents/verification-gate.md.
# Advisory ("do not block"), so a misfire does not stop work.
if $WITH_POSTTOOLUSE_HOOK; then
    POSTTOOLUSE_PROMPT="Check what was just written. If the target path is under wiki/${REPO_NAME}.wiki/*.md: did every numerical claim include its corpus / dataset / scope tag? Was every projection or estimate marked as such (not measured)? Are the back-references bidirectional with any pages this one links to? Did you also append a log_${REPO_NAME}.md entry and update index_${REPO_NAME}.md in the same session? If any answer is no, surface that briefly. Defer to wiki/agents/verification-gate.md for the canonical criteria list. This is advisory — do not block."

    if [[ ! -f "$SETTINGS_JSON" ]]; then
        cat > "$SETTINGS_JSON" <<JSONEOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          { "type": "prompt", "prompt": "${POSTTOOLUSE_PROMPT}" }
        ]
      }
    ]
  }
}
JSONEOF
        REPORT+=(".claude/settings.json: created with PostToolUse advisory hook")
    elif grep -qF '"PostToolUse"' "$SETTINGS_JSON" && grep -qF 'verification-gate.md' "$SETTINGS_JSON"; then
        REPORT+=(".claude/settings.json: PostToolUse advisory hook already registered (skipped)")
    elif command -v jq >/dev/null 2>&1; then
        TMP=$(mktemp)
        jq --arg p "$POSTTOOLUSE_PROMPT" '. + {
          "hooks": (
            (.hooks // {}) + {
              "PostToolUse": (
                (.hooks.PostToolUse // []) + [
                  {"matcher": "Write", "hooks": [{"type": "prompt", "prompt": $p}]}
                ]
              )
            }
          )
        }' "$SETTINGS_JSON" > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
        REPORT+=(".claude/settings.json: merged PostToolUse advisory hook (via jq)")
    else
        REPORT+=(".claude/settings.json: exists but PostToolUse advisory hook not registered, and jq not found. Manual edit needed.")
    fi
fi

# --- Step 6 & 7: seed personal memory (--seed-memory) ---
if $WITH_SEED_MEMORY; then
    # Encode the absolute path the way Claude Code does:
    # /Users/alice/some_project → -Users-alice-some-project
    # Replace / with -, leading - kept, dots/underscores replaced with -.
    ENCODED=$(echo "$REPO_ROOT" | tr '/._' '---')
    MEMORY_DIR="$HOME/.claude/projects/${ENCODED}/memory"
    MEMORY_FILE="$MEMORY_DIR/wiki-as-project-memory.md"
    MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"

    mkdir -p "$MEMORY_DIR"

    SEED_TEMPLATE="$TEMPLATES_DIR/memory-seed.md"
    SEED_RENDERED=$(sed "s/\${REPO_NAME}/$REPO_NAME/g" "$SEED_TEMPLATE")

    if [[ -f "$MEMORY_FILE" ]]; then
        if diff -q <(echo "$SEED_RENDERED") "$MEMORY_FILE" >/dev/null 2>&1; then
            REPORT+=("Personal memory $MEMORY_FILE: already up to date (skipped)")
        else
            REPORT+=("Personal memory $MEMORY_FILE: EXISTS with different content. Not overwritten. Diff manually if you want to update.")
        fi
    else
        echo "$SEED_RENDERED" > "$MEMORY_FILE"
        REPORT+=("Personal memory $MEMORY_FILE: seeded")
    fi

    # MEMORY.md index
    INDEX_ENTRY="- [Wiki as project memory](wiki-as-project-memory.md) — the wiki IS my memory for this project: read to recall, write to remember, proactively"
    if [[ ! -f "$MEMORY_INDEX" ]]; then
        cat > "$MEMORY_INDEX" <<MEMEOF
# Memory index — ${REPO_NAME}

${INDEX_ENTRY}
MEMEOF
        REPORT+=("Personal memory $MEMORY_INDEX: created")
    elif ! grep -qF "wiki-as-project-memory.md" "$MEMORY_INDEX"; then
        printf '\n%s\n' "$INDEX_ENTRY" >> "$MEMORY_INDEX"
        REPORT+=("Personal memory $MEMORY_INDEX: appended entry")
    else
        REPORT+=("Personal memory $MEMORY_INDEX: already references wiki-as-project-memory (skipped)")
    fi
fi

# --- Summary ---
echo ""
echo "================ Claude Code overlay setup ================"
echo "Repo:        $REPO_ROOT"
echo "Wiki:        $WIKI_DIR"
echo "Flags:       --hook=$WITH_HOOK --seed-memory=$WITH_SEED_MEMORY"
echo "-----------------------------------------------------------"
for line in "${REPORT[@]}"; do
    echo " - $line"
done
echo "==========================================================="
echo ""

# --- Next-step guidance ---
NEXT=()
CHANGES_MADE=false
for line in "${REPORT[@]}"; do
    case "$line" in
        *injected*|*appended*|*installed*|*created*|*seeded*|*"appended entry"*)
            CHANGES_MADE=true; break ;;
    esac
done
if $CHANGES_MADE; then
    NEXT+=("Review the changes above. Repo-tracked files that may have been modified:")
    NEXT+=("  - CLAUDE.md (only if 'Wiki maintenance behavior' subsection was missing)")
    NEXT+=("  - .claude/settings.json (only if SessionStart hook was merged in)")
    NEXT+=("  - .claude/hooks/session-start.sh (new, only if --hook was passed)")
    NEXT+=("These are per-team policy decisions; stage and commit selectively:")
    NEXT+=("  git add <files>")
    NEXT+=("  git commit -m \"claude-code: apply Claude Code overlay\"")
    NEXT+=("(Per-user files like .claude/settings.local.json are gitignored.)")
fi
if $WITH_SEED_MEMORY; then
    NEXT+=("")
    NEXT+=("Personal memory was seeded outside the repo at:")
    NEXT+=("  $HOME/.claude/projects/${ENCODED:-<encoded>}/memory/")
    NEXT+=("This is per-user and not version-controlled with the repo.")
fi

if [[ ${#NEXT[@]} -gt 0 ]]; then
    echo "Next steps:"
    for line in "${NEXT[@]}"; do
        echo "$line"
    done
    echo ""
fi

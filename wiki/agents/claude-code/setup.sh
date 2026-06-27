#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
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
#     4. Installs two SessionStart hooks:
#          - .claude/hooks/ensure-wiki.py (copied verbatim; clones the wiki
#            sub-repo if absent, using the same VCS as this repo).
#          - .claude/hooks/session-start.sh (from the template, substituting
#            ${REPO_NAME}; surfaces the wiki index + recent log).
#     5. Registers both in .claude/settings.json (creating or updating the
#        file conservatively) as separate SessionStart groups: ensure-wiki
#        matched to startup+resume, session-start.sh on all sources.
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

# --- Load shared library ---
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/common.sh
source "$HERE/../../../scripts/lib/common.sh"

# --- Detect project layout ---
REPO_ROOT=$(lw_repo_root)
# This overlay runs post-clone, so the canonical name is already committed
# as wiki/<name>.wiki. Read it from there rather than from the clone
# directory name (a fork or renamed clone makes the basename, and origin,
# wrong here). lw_discover_wiki_name fails loud if the wiki is absent.
REPO_NAME=$(lw_discover_wiki_name "$REPO_ROOT")
WIKI_DIR="$REPO_ROOT/wiki/${REPO_NAME}.wiki"
SCHEMA_FILE="$WIKI_DIR/SCHEMA_${REPO_NAME}.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

OVERLAY_DIR="$REPO_ROOT/wiki/agents/claude-code"
TEMPLATES_DIR="$OVERLAY_DIR/templates"
COMMANDS_DIR="$REPO_ROOT/.claude/commands"
SKILLS_DIR="$REPO_ROOT/.claude/skills"
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"

# --- Step 1: verify wiki present ---
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "ERROR: wiki not found at $WIKI_DIR" >&2
    echo "       (expected $SCHEMA_FILE)" >&2
    echo "" >&2
    echo "Run wiki/init-wiki.sh first, then re-run this script." >&2
    exit 1
fi

# --- Step 2: patch CLAUDE.md ---
# The snippet at $SNIPPET_FILE carries TWO subsections, each delimited by a
# paired sentinel (<!-- lw:memory-boundary -->, <!-- lw:wiki-maintenance -->).
# Idempotency is the presence of the opening sentinel, not a prose-heading grep
# (which false-negatived on wording drift, duplicating, and false-positived on
# the old leaked comment, F7). Each subsection injects independently, so a
# project that has one but not the other still gets the missing one.
SNIPPET_FILE="$TEMPLATES_DIR/claude-md-snippet.md"
KG_ANCHOR="### Knowledge Graph"

# Body of one subsection, read from BETWEEN its sentinel pair in the template
# (so the template's header comment never leaks in), with ${REPO_NAME}
# substituted. lw_inject_block re-wraps this body in the same sentinels.
extract_block() {
    awk -v open="<!-- lw:$1 -->" -v endm="<!-- /lw:$1 -->" '
        $0 == open { grab=1; next }
        $0 == endm { grab=0 }
        grab       { print }
    ' "$SNIPPET_FILE" | sed "s/\${REPO_NAME}/$REPO_NAME/g"
}

if [[ ! -f "$CLAUDE_MD" ]]; then
    echo "WARNING: CLAUDE.md not found at $CLAUDE_MD. Skipping CLAUDE.md patch." >&2
    lw_record_skip "CLAUDE.md: not found (skipped)"
elif [[ ! -f "$SNIPPET_FILE" ]]; then
    lw_record_skip "CLAUDE.md: template snippet not found at $SNIPPET_FILE (skipped)"
else
    patched=false
    # Migrate any pre-sentinel prose sections in place first (wrap, preserving
    # local edits), so the sentinel-based injection below recognizes them and
    # does not duplicate.
    if lw_wrap_section "$CLAUDE_MD" memory-boundary "### Memory boundary"; then
        lw_record_change "CLAUDE.md: migrated legacy 'Memory boundary' section to sentinels"; patched=true
    fi
    if lw_wrap_section "$CLAUDE_MD" wiki-maintenance "### Wiki maintenance behavior"; then
        lw_record_change "CLAUDE.md: migrated legacy 'Wiki maintenance behavior' section to sentinels"; patched=true
    fi

    # Inject each still-missing subsection. memory-boundary precedes
    # wiki-maintenance; anchor it on the latter's sentinel when present, else
    # the Knowledge Graph subsection.
    MB_ANCHOR="$KG_ANCHOR"
    grep -qF '<!-- lw:wiki-maintenance -->' "$CLAUDE_MD" 2>/dev/null && MB_ANCHOR='<!-- lw:wiki-maintenance -->'
    if lw_inject_block "$CLAUDE_MD" memory-boundary "$(extract_block memory-boundary)" "$MB_ANCHOR"; then
        lw_record_change "CLAUDE.md: injected 'Memory boundary' subsection"; patched=true
    fi
    if lw_inject_block "$CLAUDE_MD" wiki-maintenance "$(extract_block wiki-maintenance)" "$KG_ANCHOR"; then
        lw_record_change "CLAUDE.md: injected 'Wiki maintenance behavior' subsection"; patched=true
    fi
    $patched || lw_record_skip "CLAUDE.md: 'Memory boundary' and 'Wiki maintenance behavior' both already present (skipped)"
fi

# --- Step 3a: verify slash commands present ---
COMMANDS_MISSING=()
for cmd in wiki-experiment wiki-source wiki-lint; do
    if [[ ! -f "$COMMANDS_DIR/${cmd}.md" ]]; then
        COMMANDS_MISSING+=("$cmd")
    fi
done

if [[ ${#COMMANDS_MISSING[@]} -eq 0 ]]; then
    lw_record_skip ".claude/commands/: all three present (wiki-experiment, wiki-source, wiki-lint)"
else
    lw_record_skip ".claude/commands/: MISSING — ${COMMANDS_MISSING[*]} (these should be committed in the repo)"
fi

# --- Step 3b: verify model-side skills present ---
SKILLS_MISSING=()
for skill in wiki-experiment wiki-source wiki-lint; do
    if [[ ! -f "$SKILLS_DIR/${skill}.md" ]]; then
        SKILLS_MISSING+=("$skill")
    fi
done

if [[ ${#SKILLS_MISSING[@]} -eq 0 ]]; then
    lw_record_skip ".claude/skills/: all three present (wiki-experiment, wiki-source, wiki-lint)"
else
    lw_record_skip ".claude/skills/: MISSING — ${SKILLS_MISSING[*]} (these should be committed in the repo)"
fi

# --- Step 4: install SessionStart hooks (--hook) ---
# Two SessionStart hooks ship together, registered as separate matcher groups:
#   1. ensure-wiki.py    — clones the wiki sub-repo if it is absent, else
#                          fast-forwards it to upstream when the checkout is
#                          clean. Uses the same VCS that manages this repo
#                          (jj/git/...). Matched to startup+resume, the only
#                          sources where a fresh checkout may still lack the wiki.
#   2. session-start.sh  — surfaces the wiki index + recent log into context.
#                          Left unmatched (all sources) so it re-injects after
#                          /clear and /compact, when context was just lost.
# ensure-wiki.py is runtime-detecting and needs no ${REPO_NAME} substitution, so
# it is copied verbatim. It is registered behind a `command -v python3` guard so
# a host without python3 degrades to a silent no-op instead of erroring at
# session start. It is registered first so its fast-forward lands before the
# surfacing hook reads the index and log; both bail quietly when the wiki is
# absent, dirty, or already current, so a host that runs the two concurrently
# only risks surfacing a one-session-stale index, never a broken session.
if $WITH_HOOK; then
    ENSURE_TEMPLATE="$TEMPLATES_DIR/ensure-wiki.py"
    ENSURE_DEST="$HOOKS_DIR/ensure-wiki.py"
    HOOK_TEMPLATE="$TEMPLATES_DIR/session-start-hook.sh"
    HOOK_DEST="$HOOKS_DIR/session-start.sh"
    # Registered command for ensure-wiki.py: a missing python3 interpreter
    # short-circuits to `true` (exit 0) rather than failing the hook.
    ENSURE_CMD="command -v python3 >/dev/null 2>&1 && python3 .claude/hooks/ensure-wiki.py || true"

    mkdir -p "$HOOKS_DIR"

    if [[ -f "$ENSURE_DEST" ]]; then
        lw_record_skip ".claude/hooks/ensure-wiki.py: already present (not overwritten)"
    else
        cp "$ENSURE_TEMPLATE" "$ENSURE_DEST"
        chmod +x "$ENSURE_DEST"
        lw_record_change ".claude/hooks/ensure-wiki.py: installed"
    fi

    if [[ -f "$HOOK_DEST" ]]; then
        lw_record_skip ".claude/hooks/session-start.sh: already present (not overwritten)"
    else
        sed "s/\${REPO_NAME}/$REPO_NAME/g" "$HOOK_TEMPLATE" > "$HOOK_DEST"
        chmod +x "$HOOK_DEST"
        lw_record_change ".claude/hooks/session-start.sh: installed"
    fi

    # --- Step 5: register both hooks in settings.json as separate groups ---
    if [[ ! -f "$SETTINGS_JSON" ]]; then
        cat > "$SETTINGS_JSON" <<JSONEOF
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          { "type": "command", "command": "$ENSURE_CMD" }
        ]
      },
      {
        "hooks": [
          { "type": "command", "command": ".claude/hooks/session-start.sh" }
        ]
      }
    ]
  }
}
JSONEOF
        lw_record_change ".claude/settings.json: created with SessionStart hooks (ensure-wiki, session-start)"
    elif ! command -v jq >/dev/null 2>&1; then
        lw_record_skip ".claude/settings.json: exists but SessionStart hooks not registered, and jq not found. Manual edit needed: see $HOOKS_DIR"
    else
        # Register each hook as its OWN SessionStart group, appended to the
        # array. Folding them into an existing entry (as a previous version
        # did, always into index 0) makes them inherit that entry's matcher, so
        # a user whose first SessionStart entry is scoped to, say, "resume"
        # would never get ensure-wiki on startup. ensure-wiki is matched to
        # startup+resume (the sources where a fresh checkout may still lack the
        # wiki); the surfacing hook is left unmatched so it re-injects the wiki
        # index on every source, including /clear and /compact. Each is added
        # only if its command is not already registered.
        _register_ss_hook() {  # $1=command  $2=matcher (""=all sources)  $3=label  $4=dedup key
            local cmd="$1" matcher="$2" label="$3" key="$4" tmp
            if grep -qF "$key" "$SETTINGS_JSON"; then
                lw_record_skip ".claude/settings.json: $label hook already registered (skipped)"
                return 0
            fi
            tmp=$(mktemp)
            jq --arg cmd "$cmd" --arg matcher "$matcher" '
              .hooks = (.hooks // {})
              | .hooks.SessionStart = ((.hooks.SessionStart // []) + [
                  (if $matcher == "" then {} else {matcher: $matcher} end)
                  + {hooks: [{type: "command", command: $cmd}]}
                ])
            ' "$SETTINGS_JSON" > "$tmp" && mv "$tmp" "$SETTINGS_JSON"
            lw_record_change ".claude/settings.json: merged $label SessionStart hook (via jq)"
        }
        _register_ss_hook "$ENSURE_CMD" "startup|resume" "ensure-wiki.py" ".claude/hooks/ensure-wiki.py"
        _register_ss_hook ".claude/hooks/session-start.sh" "" "session-start.sh" ".claude/hooks/session-start.sh"
    fi
fi

# --- PostToolUse advisory hook (--posttooluse-hook) ---
# Installs a command hook that fires after every Write or Edit. When the
# written file is a wiki page, the hook script prints a reminder to run
# the Verification Gate before committing. It is a command hook on
# purpose: exit 0 makes it purely advisory (the action proceeds, stdout
# becomes context). A prompt hook cannot be advisory (sandboxed, allow or
# block only), and an earlier prompt-hook version wrongly stopped the
# agent mid-ingest. The script reminds; the agent runs the actual gate.
if $WITH_POSTTOOLUSE_HOOK; then
    PTU_HOOK_TEMPLATE="$TEMPLATES_DIR/posttooluse-hook.sh"
    PTU_HOOK_DEST="$HOOKS_DIR/posttooluse-hook.sh"

    mkdir -p "$HOOKS_DIR"

    if [[ -f "$PTU_HOOK_DEST" ]]; then
        lw_record_skip ".claude/hooks/posttooluse-hook.sh: already present (not overwritten)"
    else
        sed "s/\${REPO_NAME}/$REPO_NAME/g" "$PTU_HOOK_TEMPLATE" > "$PTU_HOOK_DEST"
        chmod +x "$PTU_HOOK_DEST"
        lw_record_change ".claude/hooks/posttooluse-hook.sh: installed"
    fi

    # Register the hook in settings.json: matcher Write|Edit, type command.
    if [[ -f "$SETTINGS_JSON" ]] && grep -qF '"posttooluse-hook.sh"' "$SETTINGS_JSON"; then
        lw_record_skip ".claude/settings.json: PostToolUse advisory hook already registered (skipped)"
    elif command -v jq >/dev/null 2>&1; then
        TMP=$(mktemp)
        if [[ -f "$SETTINGS_JSON" ]]; then
            jq '. + {
              "hooks": (
                (.hooks // {}) + {
                  "PostToolUse": (
                    (.hooks.PostToolUse // []) + [
                      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": ".claude/hooks/posttooluse-hook.sh"}]}
                    ]
                  )
                }
              )
            }' "$SETTINGS_JSON" > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
            lw_record_change ".claude/settings.json: merged PostToolUse advisory hook (via jq)"
        else
            jq -n '{
              "hooks": {
                "PostToolUse": [
                  {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": ".claude/hooks/posttooluse-hook.sh"}]}
                ]
              }
            }' > "$TMP" && mv "$TMP" "$SETTINGS_JSON"
            lw_record_change ".claude/settings.json: created with PostToolUse advisory hook (via jq)"
        fi
    else
        lw_record_skip ".claude/settings.json: exists but PostToolUse advisory hook not registered, and jq not found. Manual edit needed: see $PTU_HOOK_DEST"
    fi
fi

# --- Step 6 & 7: seed personal memory (--seed-memory) ---
if $WITH_SEED_MEMORY; then
    # Per-project memory dir, mirroring Claude Code's own cwd encoding
    # (and honoring $CLAUDE_CONFIG_DIR). See scripts/lib/claude.sh.
    MEMORY_DIR=$(lw_memory_dir "$REPO_ROOT")
    MEMORY_FILE="$MEMORY_DIR/wiki-as-project-memory.md"
    MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"

    mkdir -p "$MEMORY_DIR"

    SEED_TEMPLATE="$TEMPLATES_DIR/memory-seed.md"
    SEED_RENDERED=$(sed "s/\${REPO_NAME}/$REPO_NAME/g" "$SEED_TEMPLATE")

    if [[ -f "$MEMORY_FILE" ]]; then
        if diff -q <(echo "$SEED_RENDERED") "$MEMORY_FILE" >/dev/null 2>&1; then
            lw_record_skip "Personal memory $MEMORY_FILE: already up to date (skipped)"
        else
            lw_record_skip "Personal memory $MEMORY_FILE: EXISTS with different content. Not overwritten. Diff manually if you want to update."
        fi
    else
        echo "$SEED_RENDERED" > "$MEMORY_FILE"
        lw_record_change "Personal memory $MEMORY_FILE: seeded"
    fi

    # MEMORY.md index
    INDEX_ENTRY="- [Wiki as project memory](wiki-as-project-memory.md) — the wiki IS my memory for this project: read to recall, write to remember, proactively"
    if [[ ! -f "$MEMORY_INDEX" ]]; then
        cat > "$MEMORY_INDEX" <<MEMEOF
# Memory index — ${REPO_NAME}

${INDEX_ENTRY}
MEMEOF
        lw_record_change "Personal memory $MEMORY_INDEX: created"
    elif ! grep -qF "wiki-as-project-memory.md" "$MEMORY_INDEX"; then
        printf '\n%s\n' "$INDEX_ENTRY" >> "$MEMORY_INDEX"
        lw_record_change "Personal memory $MEMORY_INDEX: appended entry"
    else
        lw_record_skip "Personal memory $MEMORY_INDEX: already references wiki-as-project-memory (skipped)"
    fi
fi

# --- Summary ---
echo ""
echo "================ Claude Code overlay setup ================"
echo "Repo:        $REPO_ROOT"
echo "Wiki:        $WIKI_DIR"
echo "Flags:       --hook=$WITH_HOOK --seed-memory=$WITH_SEED_MEMORY"
echo "-----------------------------------------------------------"
lw_print_report
echo "==========================================================="
echo ""

# --- Next-step guidance ---
NEXT=()
if lw_changed_p; then
    NEXT+=("Review the changes above. Repo-tracked files that may have been modified:")
    NEXT+=("  - CLAUDE.md (only if 'Wiki maintenance behavior' subsection was missing)")
    NEXT+=("  - .claude/settings.json (only if SessionStart hook was merged in)")
    NEXT+=("  - .claude/hooks/ensure-wiki.py (new, only if --hook was passed)")
    NEXT+=("  - .claude/hooks/session-start.sh (new, only if --hook was passed)")
    NEXT+=("These are per-team policy decisions; stage and commit selectively:")
    NEXT+=("  git add <files>")
    NEXT+=("  git commit -m \"claude-code: apply Claude Code overlay\"")
    NEXT+=("(Per-user files like .claude/settings.local.json are gitignored.)")
fi
if $WITH_SEED_MEMORY; then
    NEXT+=("")
    NEXT+=("Personal memory was seeded outside the repo at:")
    NEXT+=("  $MEMORY_DIR/")
    NEXT+=("This is per-user and not version-controlled with the repo.")
fi

if [[ ${#NEXT[@]} -gt 0 ]]; then
    echo "Next steps:"
    for line in "${NEXT[@]}"; do
        echo "$line"
    done
    echo ""
fi

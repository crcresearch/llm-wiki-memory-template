#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# setup.sh — Cursor overlay on top of an llm-wiki project.
#
# This script is the Cursor-specific layer of the llm-wiki pattern, parallel
# to wiki/agents/claude-code/setup.sh. wiki/init-wiki.sh stays agent-agnostic.
#
# Usage:
#   ./wiki/agents/cursor/setup.sh                     # base: verify rule + skills and CLAUDE.md patch
#   ./wiki/agents/cursor/setup.sh --hook              # + sessionStart hooks (ensure-wiki + wiki index/log)
#   ./wiki/agents/cursor/setup.sh --posttooluse-hook  # + postToolUse advisory gate nudge
#   ./wiki/agents/cursor/setup.sh --legacy            # also install legacy .cursorrules
#                                                     # (for Cursor builds that don't read .mdc rules)
#   ./wiki/agents/cursor/setup.sh --all               # --hook + --posttooluse-hook + --legacy
#
# What it does:
#   Base mode:
#     1. Verifies the wiki is present (else points to init-wiki.sh).
#     2. Patches CLAUDE.md with the "Memory boundary" and "Wiki maintenance
#        behavior" subsections, if not already present. Same markers as the
#        Claude Code overlay; if both overlays are active, only the first one
#        to run patches each subsection.
#     3. Reports presence/absence of .cursor/rules/wiki-as-memory.mdc and
#        .cursor/skills/wiki-{experiment,source,lint}/SKILL.md. These ship
#        with the repository and the script only verifies them.
#
#   --hook:
#     4. Installs two sessionStart hooks into .cursor/hooks/, in order:
#          - ensure-wiki.sh (copied verbatim; a thin adapter over the shared
#            wiki/agents/templates/ensure-wiki.py that clones/fast-forwards
#            the wiki sub-repo).
#          - session-start.sh (from the template, substituting ${REPO_NAME};
#            surfaces the wiki index + recent log into additional_context).
#     5. Registers both in .cursor/hooks.json under sessionStart, ensure-wiki
#        first (creating or updating the file conservatively).
#
#   --posttooluse-hook:
#     6. Installs .cursor/hooks/posttooluse-hook.sh (advisory) and registers
#        it under postToolUse with matcher "Write|Edit". After a Write/Edit
#        to a wiki page it nudges the agent to read discipline-gates.md and
#        run the verification-gate.md procedure before committing. Does not
#        block.
#
#   --legacy:
#     7. Copies .cursorrules.template -> .cursorrules at the repo root,
#        substituting {{REPO_NAME}}. Skipped if .cursorrules already exists.
#
# The always-applied rule wiki-as-memory.mdc remains the durable fallback if
# sessionStart context injection is unavailable or flaky in a given Cursor
# build. The hook is the complementary path: live wiki index + recent log at
# turn 0, so the agent treats the wiki as memory rather than search.
#
# Does not commit anything. Does not push.
#

set -euo pipefail

WITH_LEGACY=false
WITH_HOOK=false
WITH_POSTTOOLUSE_HOOK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --legacy) WITH_LEGACY=true; shift ;;
        --hook) WITH_HOOK=true; shift ;;
        --posttooluse-hook) WITH_POSTTOOLUSE_HOOK=true; shift ;;
        --all) WITH_HOOK=true; WITH_POSTTOOLUSE_HOOK=true; WITH_LEGACY=true; shift ;;
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

RULES_DIR="$REPO_ROOT/.cursor/rules"
SKILLS_DIR="$REPO_ROOT/.cursor/skills"
HOOKS_DIR="$REPO_ROOT/.cursor/hooks"
HOOKS_JSON="$REPO_ROOT/.cursor/hooks.json"
TEMPLATES_DIR="$HERE/templates"
CURSORRULES_DEST="$REPO_ROOT/.cursorrules"
CURSORRULES_TEMPLATE="$REPO_ROOT/.cursorrules.template"

# --- Step 1: verify wiki present ---
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "ERROR: wiki not found at $WIKI_DIR" >&2
    echo "       (expected $SCHEMA_FILE)" >&2
    echo "" >&2
    echo "Run wiki/init-wiki.sh first, then re-run this script." >&2
    exit 1
fi

# --- Step 2: patch CLAUDE.md (shared with Claude Code overlay) ---
# The snippet ships with the Claude Code overlay and carries TWO subsections,
# each delimited by a paired sentinel (<!-- lw:memory-boundary -->,
# <!-- lw:wiki-maintenance -->). Idempotency is the opening sentinel, not a
# prose-heading grep (F7). Same path as claude-code/setup.sh, so whichever
# overlay runs first injects and the other skips; a derived project missing one
# subsection still gets it.
SNIPPET_FILE="$REPO_ROOT/wiki/agents/claude-code/templates/claude-md-snippet.md"
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
    lw_record_skip "CLAUDE.md: not found (skipped). Run instantiate.sh to generate it."
elif [[ ! -f "$SNIPPET_FILE" ]]; then
    lw_record_skip "CLAUDE.md: template snippet not found at $SNIPPET_FILE (skipped)"
else
    patched=false
    # Migrate any pre-sentinel prose sections in place first (wrap, preserving
    # local edits), so the sentinel-based injection below does not duplicate.
    if lw_wrap_section "$CLAUDE_MD" memory-boundary "### Memory boundary"; then
        lw_record_change "CLAUDE.md: migrated legacy 'Memory boundary' section to sentinels"; patched=true
    fi
    if lw_wrap_section "$CLAUDE_MD" wiki-maintenance "### Wiki maintenance behavior"; then
        lw_record_change "CLAUDE.md: migrated legacy 'Wiki maintenance behavior' section to sentinels"; patched=true
    fi

    # memory-boundary precedes wiki-maintenance; anchor on the latter's
    # sentinel when present, else the Knowledge Graph subsection.
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

# --- Step 3a: verify always-applied wiki-as-memory rule present ---
if [[ -f "$RULES_DIR/wiki-as-memory.mdc" ]]; then
    lw_record_skip ".cursor/rules/wiki-as-memory.mdc: present"
else
    lw_record_skip ".cursor/rules/wiki-as-memory.mdc: MISSING (should be committed in the repo)"
fi

# --- Step 3b: verify project skills present ---
SKILLS_MISSING=()
for skill in wiki-experiment wiki-source wiki-lint; do
    if [[ ! -f "$SKILLS_DIR/${skill}/SKILL.md" ]]; then
        SKILLS_MISSING+=("$skill")
    fi
done

if [[ ${#SKILLS_MISSING[@]} -eq 0 ]]; then
    lw_record_skip ".cursor/skills/: all three present (wiki-experiment, wiki-source, wiki-lint)"
else
    lw_record_skip ".cursor/skills/: MISSING — ${SKILLS_MISSING[*]} (these should be committed in the repo)"
fi

# --- Step 4: install sessionStart hooks (--hook) ---
# Two sessionStart hooks ship together, registered as separate entries in
# .cursor/hooks.json IN ORDER:
#   1. ensure-wiki.sh   — a thin adapter over the shared
#                         wiki/agents/templates/ensure-wiki.py that clones the
#                         wiki sub-repo if absent, else fast-forwards it when
#                         the checkout is clean. Copied verbatim (uses paths
#                         relative to the repo root; no ${REPO_NAME}).
#   2. session-start.sh — surfaces the wiki index + recent log into
#                         additional_context. Rendered with ${REPO_NAME}.
# ensure-wiki.sh is registered first so its clone/fast-forward lands before
# the surfacing hook reads the index and log. Both fail open (emit
# {"additional_context":""} and exit 0) when the wiki is absent, dirty, or
# already current, so registration order is an optimisation, not a
# correctness requirement.
if $WITH_HOOK; then
    ENSURE_TEMPLATE="$TEMPLATES_DIR/ensure-wiki-cursor.sh"
    ENSURE_DEST="$HOOKS_DIR/ensure-wiki.sh"
    ENSURE_CMD=".cursor/hooks/ensure-wiki.sh"
    HOOK_TEMPLATE="$TEMPLATES_DIR/session-start-hook.sh"
    HOOK_DEST="$HOOKS_DIR/session-start.sh"
    HOOK_CMD=".cursor/hooks/session-start.sh"

    mkdir -p "$HOOKS_DIR"

    # Install ensure-wiki.sh (copied verbatim; needs no substitution).
    if [[ ! -f "$ENSURE_TEMPLATE" ]]; then
        lw_record_skip ".cursor/hooks/ensure-wiki.sh: template not found at $ENSURE_TEMPLATE (skipped)"
    elif [[ -f "$ENSURE_DEST" ]]; then
        lw_record_skip ".cursor/hooks/ensure-wiki.sh: already present (not overwritten)"
    else
        cp "$ENSURE_TEMPLATE" "$ENSURE_DEST"
        chmod +x "$ENSURE_DEST"
        lw_record_change ".cursor/hooks/ensure-wiki.sh: installed"
    fi

    # Install session-start.sh (rendered with ${REPO_NAME}).
    if [[ ! -f "$HOOK_TEMPLATE" ]]; then
        lw_record_skip ".cursor/hooks/session-start.sh: template not found at $HOOK_TEMPLATE (skipped)"
    elif [[ -f "$HOOK_DEST" ]]; then
        lw_record_skip ".cursor/hooks/session-start.sh: already present (not overwritten)"
    else
        sed "s/\${REPO_NAME}/$REPO_NAME/g" "$HOOK_TEMPLATE" > "$HOOK_DEST"
        chmod +x "$HOOK_DEST"
        lw_record_change ".cursor/hooks/session-start.sh: installed"
    fi

    # Register both commands in .cursor/hooks.json (Cursor schema:
    # version + hooks.<event>[].command), ensure-wiki first. A fresh file is
    # written with BOTH entries in order so the common install path needs no
    # jq; merging into an existing hooks.json appends each missing command
    # (jq-only, matching the Claude overlay's settings.json merge contract).
    if [[ ! -f "$HOOKS_JSON" ]]; then
        cat > "$HOOKS_JSON" <<JSONEOF
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "command": "$ENSURE_CMD"
      },
      {
        "command": "$HOOK_CMD"
      }
    ]
  }
}
JSONEOF
        lw_record_change ".cursor/hooks.json: created with sessionStart hooks (ensure-wiki, session-start)"
    else
        _register_ss_cmd() {  # $1=command  $2=label
            local cmd="$1" label="$2" tmp
            if grep -qF "$cmd" "$HOOKS_JSON"; then
                lw_record_skip ".cursor/hooks.json: $label sessionStart hook already registered (skipped)"
            elif ! command -v jq >/dev/null 2>&1; then
                lw_record_skip ".cursor/hooks.json: exists but $label hook not registered, and jq not found. Manual edit needed: see $HOOKS_DIR"
            else
                tmp=$(mktemp)
                jq --arg cmd "$cmd" '
                  .version = (.version // 1)
                  | .hooks = (.hooks // {})
                  | .hooks.sessionStart = ((.hooks.sessionStart // []) + [{command: $cmd}])
                ' "$HOOKS_JSON" > "$tmp" && mv "$tmp" "$HOOKS_JSON"
                lw_record_change ".cursor/hooks.json: merged $label sessionStart hook (via jq)"
            fi
        }
        _register_ss_cmd "$ENSURE_CMD" "ensure-wiki.sh"
        _register_ss_cmd "$HOOK_CMD" "session-start.sh"
    fi
fi

# --- Step 6: install postToolUse advisory hook (--posttooluse-hook) ---
# Fires after every Write or Edit. When the written file is a wiki page the
# hook script emits additional_context reminding the agent to apply the
# discipline gates and run the Verification Gate before committing. Advisory
# only (postToolUse returns additional_context, never blocks), mirroring the
# Claude Code posttooluse-hook.sh contract. The script keeps a belt-and-
# suspenders path filter so it stays correct even if the matcher is loosened.
if $WITH_POSTTOOLUSE_HOOK; then
    PTU_HOOK_TEMPLATE="$TEMPLATES_DIR/posttooluse-hook.sh"
    PTU_HOOK_DEST="$HOOKS_DIR/posttooluse-hook.sh"
    PTU_HOOK_CMD=".cursor/hooks/posttooluse-hook.sh"

    mkdir -p "$HOOKS_DIR"

    if [[ ! -f "$PTU_HOOK_TEMPLATE" ]]; then
        lw_record_skip ".cursor/hooks/posttooluse-hook.sh: template not found at $PTU_HOOK_TEMPLATE (skipped)"
    elif [[ -f "$PTU_HOOK_DEST" ]]; then
        lw_record_skip ".cursor/hooks/posttooluse-hook.sh: already present (not overwritten)"
    else
        sed "s/\${REPO_NAME}/$REPO_NAME/g" "$PTU_HOOK_TEMPLATE" > "$PTU_HOOK_DEST"
        chmod +x "$PTU_HOOK_DEST"
        lw_record_change ".cursor/hooks/posttooluse-hook.sh: installed"
    fi

    # Register under postToolUse with matcher "Write|Edit" (JS regex on tool
    # type per Cursor docs). Cursor schema: version + hooks.<event>[].
    if [[ ! -f "$HOOKS_JSON" ]]; then
        cat > "$HOOKS_JSON" <<JSONEOF
{
  "version": 1,
  "hooks": {
    "postToolUse": [
      {
        "command": "$PTU_HOOK_CMD",
        "matcher": "Write|Edit"
      }
    ]
  }
}
JSONEOF
        lw_record_change ".cursor/hooks.json: created with postToolUse advisory hook"
    elif grep -qF "$PTU_HOOK_CMD" "$HOOKS_JSON"; then
        lw_record_skip ".cursor/hooks.json: postToolUse advisory hook already registered (skipped)"
    elif ! command -v jq >/dev/null 2>&1; then
        lw_record_skip ".cursor/hooks.json: exists but postToolUse hook not registered, and jq not found. Manual edit needed: see $PTU_HOOK_DEST"
    else
        tmp=$(mktemp)
        jq --arg cmd "$PTU_HOOK_CMD" '
          .version = (.version // 1)
          | .hooks = (.hooks // {})
          | .hooks.postToolUse = ((.hooks.postToolUse // []) + [{command: $cmd, matcher: "Write|Edit"}])
        ' "$HOOKS_JSON" > "$tmp" && mv "$tmp" "$HOOKS_JSON"
        lw_record_change ".cursor/hooks.json: merged postToolUse advisory hook (via jq)"
    fi
fi

# --- Step 7: install legacy .cursorrules (--legacy) ---
if $WITH_LEGACY; then
    if [[ -f "$CURSORRULES_DEST" ]]; then
        lw_record_skip ".cursorrules: already present (skipped)"
    elif [[ ! -f "$CURSORRULES_TEMPLATE" ]]; then
        lw_record_skip ".cursorrules: template not found at $CURSORRULES_TEMPLATE (skipped)"
    else
        sed "s/{{REPO_NAME}}/$REPO_NAME/g" "$CURSORRULES_TEMPLATE" > "$CURSORRULES_DEST"
        lw_record_change ".cursorrules: created from template (legacy single-file Cursor format)"
    fi
fi

# --- Summary ---
echo ""
echo "================ Cursor overlay setup ================"
echo "Repo:        $REPO_ROOT"
echo "Wiki:        $WIKI_DIR"
echo "Flags:       --hook=$WITH_HOOK --posttooluse-hook=$WITH_POSTTOOLUSE_HOOK --legacy=$WITH_LEGACY"
echo "------------------------------------------------------"
lw_print_report
echo "======================================================"
echo ""

if lw_changed_p; then
    echo "Next steps:"
    echo "  Review the changes above, then stage and commit:"
    echo "    git add CLAUDE.md .cursor/ ${WITH_LEGACY:+.cursorrules}"
    echo "    git commit -m \"cursor: apply Cursor overlay (setup.sh)\""
    echo ""
    if $WITH_HOOK; then
        echo "  sessionStart hooks: start a new Cursor agent chat and check the"
        echo "  Hooks output channel to confirm ensure-wiki.sh and session-start.sh"
        echo "  ran (in that order). Cursor reloads hooks.json on save; restart"
        echo "  Cursor if they do not appear."
        echo ""
    fi
    if $WITH_POSTTOOLUSE_HOOK; then
        echo "  postToolUse hook: edit a wiki page in a Cursor agent chat and"
        echo "  confirm posttooluse-hook.sh fires (Hooks output channel), nudging"
        echo "  toward the discipline + verification gates. Advisory; never blocks."
        echo ""
    fi
fi

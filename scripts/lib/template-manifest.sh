#!/usr/bin/env bash
# Canonical enumeration of every file the template owns.
#
# Sourced by:
#   - scripts/update-from-template.sh  (sync into existing derived projects)
#   - scripts/check-template-version.sh (drift report)
#   - scripts/adopt.sh                  (ADD allowlist + HOST_OWNED grants)
#
# To add a template-synced file, edit this file and nothing else. The three
# consumer scripts assemble their working set from these arrays; the unit
# fixture scripts/test/tests/unit/manifest-shape/ enforces the cross-array
# invariants (no double-ownership, every HOST_OWNED has a known grant type,
# every SUBSTITUTE entry is in one of the sync arrays).
#
# Bash 3.2 compatible: no associative arrays, plain string indexing.

[[ -n "${_LW_MANIFEST_SOURCED:-}" ]] && return 0
_LW_MANIFEST_SOURCED=1

# Files the template owns end-to-end. Synced regardless of which overlay
# (claude-code, cursor) the host has installed. update-from-template
# overwrites when the host hasn't modified them; adopt ADDs when absent.
TEMPLATE_SHARED_INFRA=(
    "llm-wiki.md"
    "wiki/init-wiki.sh"
    # Synced VERBATIM (deliberately not in TEMPLATE_SUBSTITUTE_FILES): its
    # {{REPO_NAME}} markers are stamped by init-wiki.sh's wiki/*.md.template
    # loop at wiki-init time, in the host. Substituting at sync time would
    # bake one project's name into a reusable template. Absent from this
    # list, adopted wikis had SCHEMA [Edge-Types] links with no page (#75).
    "wiki/Edge-Types.md.template"
    "wiki/agents/README.md"
    "wiki/agents/discipline-gates.md"
    "wiki/agents/verification-gate.md"
    "wiki/agents/wiki-write-protocol.md"
    "scripts/update-from-template.sh"
    "scripts/check-template-version.sh"
    "scripts/enable-feature.sh"
    "scripts/disable-feature.sh"
    "scripts/lib/install-feature.sh"
    # The manifest ships ITSELF: update-from-template.sh and
    # check-template-version.sh (both synced above) source it from the
    # HOST's own scripts/lib/. Absent from this list, every adopted host's
    # sync tooling died at its source line (#74).
    "scripts/lib/template-manifest.sh"
    "scripts/lib/common.sh"
    "scripts/lib/git.sh"
    "scripts/lib/identity.sh"
    "scripts/lib/text.sh"
    "scripts/lib/report.sh"
    "scripts/lib/claude.sh"
    "scripts/lib/sys.sh"
    "features/README.md"
    "scripts/wiki-write-protocol/README.md"
    "scripts/wiki-write-protocol/protocol.sh"
    "scripts/wiki-write-protocol/sandbox.sh"
    "scripts/wiki-write-protocol/run-all.sh"
    "scripts/wiki-write-protocol/scenarios/01-different-pages/run.sh"
    "scripts/wiki-write-protocol/scenarios/02-different-sections/run.sh"
    "scripts/wiki-write-protocol/scenarios/03-same-section/run.sh"
    "scripts/wiki-write-protocol/scenarios/04-index-union/run.sh"
    "scripts/wiki-write-protocol/scenarios/05-log-append/run.sh"
    "scripts/wiki-write-protocol/scenarios/06-push-race/run.sh"
    "scripts/wiki-write-protocol/scenarios/07-livelock-retry/run.sh"
    "scripts/wiki-write-protocol/scenarios/08-session-start-auto-pull/run.sh"
    "scripts/wiki-write-protocol/scenarios/09-session-start-divergent/run.sh"
)

# Claude Code overlay files. Active when adopt is invoked with
# --agent=claude-code, or when update/check detects an existing claude
# overlay on the host (presence of .claude/ or wiki/agents/claude-code/).
TEMPLATE_OVERLAY_CLAUDE=(
    ".claude/commands/wiki-experiment.md"
    ".claude/commands/wiki-source.md"
    ".claude/commands/wiki-lint.md"
    ".claude/skills/wiki-experiment.md"
    ".claude/skills/wiki-source.md"
    ".claude/skills/wiki-lint.md"
    "wiki/agents/claude-code/setup.sh"
    "wiki/agents/claude-code/README.md"
    "wiki/agents/claude-code/templates/claude-md-snippet.md"
    "wiki/agents/claude-code/templates/memory-seed.md"
    "wiki/agents/claude-code/templates/session-start-hook.sh"
    "wiki/agents/claude-code/templates/posttooluse-hook.sh"
    "wiki/agents/claude-code/templates/ensure-wiki.py"
)

# Cursor overlay files. Active when adopt is invoked with --agent=cursor
# (currently refused at parse-time but enumerated here so detection-mode
# in update/check can sync them when the host has a .cursor/ overlay).
TEMPLATE_OVERLAY_CURSOR=(
    ".cursor/rules/wiki-as-memory.mdc"
    ".cursor/rules/wiki-experiment.mdc"
    ".cursor/rules/wiki-source.mdc"
    ".cursor/rules/wiki-lint.mdc"
    "wiki/agents/cursor/setup.sh"
    "wiki/agents/cursor/README.md"
)

# Files where {{REPO_NAME}} must be substituted by $REPO_NAME at copy
# time. Centralised so instantiate.sh, update-from-template.sh, and any
# future consumer share the same list.
#
# Deliberate exclusions:
#  - wiki/agents/claude-code/templates/ensure-wiki.py: runtime-detecting;
#    every $REPO_NAME reference is inside a Python docstring or comment,
#    not literal {{REPO_NAME}}.
#  - wiki/agents/claude-code/templates/posttooluse-hook.sh: the
#    ${REPO_NAME} expression lives inside a single-quoted heredoc that
#    setup.sh ships verbatim. Substituting it here would not reach the
#    installed hook. Tracked as a separate issue; out of scope for this
#    manifest.
#  - wiki/agents/claude-code/templates/{claude-md-snippet.md,
#    session-start-hook.sh, memory-seed.md}: scanned and confirmed to
#    contain no {{REPO_NAME}} marker. Listing them would lie about the
#    contract.
TEMPLATE_SUBSTITUTE_FILES=(
    ".claude/commands/wiki-experiment.md"
    ".claude/commands/wiki-source.md"
    ".claude/commands/wiki-lint.md"
    ".claude/skills/wiki-experiment.md"
    ".claude/skills/wiki-source.md"
    ".claude/skills/wiki-lint.md"
    ".cursor/rules/wiki-as-memory.mdc"
    ".cursor/rules/wiki-experiment.mdc"
    ".cursor/rules/wiki-source.mdc"
    ".cursor/rules/wiki-lint.mdc"
)

# Host-owned: the template defines an operation type for the path but the
# host owns the content. update-from-template ignores these entirely; adopt
# uses them to seed DEFAULT_GRANTS when no .llm-wiki-adopt-grants.yml is
# present. Format: "path|operation-type" where operation-type matches the
# known_grant_type vocabulary (managed-block, append-only, merge).
TEMPLATE_HOST_OWNED=(
    "CLAUDE.md|managed-block"
    ".gitignore|append-only"
    ".claude/settings.json|merge"
)

# Documentation only. These never reach a derived project: instantiate.sh
# consumes the .template variants and self-deletes; TEMPLATE_ONE_SHOT is the
# manifest record so future code can reference what was deliberately
# excluded from sync.
# shellcheck disable=SC2034  # consumed by docs/tests, not by sync logic
TEMPLATE_ONE_SHOT=(
    "scripts/instantiate.sh"
    "CLAUDE.md.template"
    "README.md.template"
    ".claude/settings.json.template"
    ".cursorrules.template"
)

# --- Accessors --------------------------------------------------------------

# True if $1 is in TEMPLATE_SUBSTITUTE_FILES.
lw_manifest_needs_substitution() {
    local f="$1" s
    for s in "${TEMPLATE_SUBSTITUTE_FILES[@]}"; do
        [[ "$f" == "$s" ]] && return 0
    done
    return 1
}

# Echo the active file set for the host on stdout, one path per line.
# Two calling modes:
#   adopt:        lw_manifest_assemble_active_files ""          "$AGENT"
#   update/check: lw_manifest_assemble_active_files "$REPO_ROOT" ""
# The empty slot disables that mode. When agent is empty AND repo_root is
# set, overlays are included based on directory presence on disk.
lw_manifest_assemble_active_files() {
    local repo_root="$1" agent="$2" f
    for f in "${TEMPLATE_SHARED_INFRA[@]}"; do
        printf '%s\n' "$f"
    done
    if [[ "$agent" == "claude-code" ]] \
       || { [[ -z "$agent" ]] && [[ -n "$repo_root" ]] \
            && { [[ -d "$repo_root/.claude" ]] || [[ -d "$repo_root/wiki/agents/claude-code" ]]; }; }; then
        for f in "${TEMPLATE_OVERLAY_CLAUDE[@]}"; do
            printf '%s\n' "$f"
        done
    fi
    if [[ "$agent" == "cursor" ]] \
       || { [[ -z "$agent" ]] && [[ -n "$repo_root" ]] \
            && { [[ -d "$repo_root/.cursor" ]] || [[ -d "$repo_root/wiki/agents/cursor" ]]; }; }; then
        for f in "${TEMPLATE_OVERLAY_CURSOR[@]}"; do
            printf '%s\n' "$f"
        done
    fi
}

# Echo the HOST_OWNED operation type for $1, or empty string if not host-
# owned. Used by adopt to look up which grant type a host-owned path expects.
lw_manifest_known_grant_type() {
    local p="$1" entry
    for entry in "${TEMPLATE_HOST_OWNED[@]}"; do
        [[ "${entry%%|*}" == "$p" ]] && { echo "${entry##*|}"; return 0; }
    done
    echo ""
}

# Echo the sentinel label for $1's append-only payload, or empty if none.
# managed-block grants intentionally return empty: the overlay's setup.sh
# injects two paired-sentinel blocks rather than a single wrapper, so adopt
# does not own those names.
lw_manifest_known_grant_sentinel() {
    case "$1" in
        .gitignore)  echo "lw:wiki-rules" ;;
        *)           echo "" ;;
    esac
}

# Echo the canonical payload for $1's append-only grant. Inserted between
# paired lw_inject_block sentinels at the target's end-of-file.
lw_manifest_known_grant_payload() {
    case "$1" in
        .gitignore)
            cat <<'EOF'
# wiki sub-repo: separate git remote, not part of the host's tracked tree
wiki/*.wiki/
EOF
            ;;
    esac
}

#!/usr/bin/env bash
# adopt.sh — additive overlay of llm-wiki-memory-template into an existing
# repository.
#
# STATUS: STUB. Performs --dry-run only; classifies the ADD allowlist
# against the target repo (ADD / SKIP / REFUSE) and prints a report.
# Does NOT apply any changes, does NOT read TOUCH grants, does NOT
# init the wiki sub-repo, does NOT install agent overlays or features.
#
# Design:
#   https://github.com/crcresearch/llm-wiki-memory-template/wiki/Adopt-Existing-Repo-Design
# Issue:
#   https://github.com/crcresearch/llm-wiki-memory-template/issues/6

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$HERE/.." && pwd)"

# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

# --- ADD allowlist ----------------------------------------------------------
# Paths the template would contribute. Each is relative to TEMPLATE_ROOT
# (source) AND to the target (destination), so they're compared 1-to-1.
# Subset of the wiki design's full allowlist; sufficient to exercise the
# classification logic. Will grow as the stub matures.
ADD_ALLOWLIST=(
    llm-wiki.md
    wiki/init-wiki.sh
    wiki/agents/discipline-gates.md
    wiki/agents/verification-gate.md
    scripts/lib/common.sh
    scripts/lib/git.sh
    scripts/lib/identity.sh
    scripts/lib/text.sh
    scripts/lib/report.sh
    scripts/lib/claude.sh
    scripts/lib/sys.sh
    scripts/lib/install-feature.sh
    scripts/update-from-template.sh
    scripts/check-template-version.sh
    scripts/enable-feature.sh
    scripts/disable-feature.sh
)

# --- KNOWN_GRANTS -----------------------------------------------------------
# Per-target operation the template knows how to perform.  Hosts opt in by
# listing a target in .llm-wiki-adopt-grants.yml with the matching grant
# type. Anything not enumerated here can only be classified as REFUSE-by-
# default (no grant), even if a host's grants file mentions it.  Bash 3.2
# compatible: case lookups instead of associative arrays.
known_grant_type() {
    case "$1" in
        CLAUDE.md)              echo "managed-block" ;;
        .gitignore)             echo "append-only" ;;
        .claude/settings.json)  echo "merge" ;;
        *)                      echo "" ;;
    esac
}

# Sentinel label used by managed-block / append-only mechanisms for each
# granted target. Reported in the dry-run so reviewers see exactly what
# region adopt would maintain.
known_grant_sentinel() {
    case "$1" in
        CLAUDE.md)   echo "lw:wiki-section" ;;
        .gitignore)  echo "lw:wiki-rules"  ;;
        *)           echo ""               ;;
    esac
}

# --- parse_grants_file ------------------------------------------------------
# Minimal YAML reader for the .llm-wiki-adopt-grants.yml host file. Accepts
# only the flat 'grants:' dictionary; anything else is ignored. Each emitted
# line has the form '<path>|<type>'. Comments (#) and blank lines are
# stripped. Robust against trailing whitespace; not robust against quoted
# keys, multi-line values, or nested structures (deliberately out of scope:
# the grants file is meant to be tiny and hand-authored).
parse_grants_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    awk '
        # toggle in_grants only on top-level "grants:" key, not on nested ones
        /^grants:[[:space:]]*$/ { in_grants = 1; next }
        # any other top-level key (line starting with non-space, non-#) closes the section
        /^[^[:space:]#]/ { in_grants = 0; next }
        # within grants, look for "  key: value" lines
        in_grants && /^[[:space:]]+[^[:space:]#]/ {
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]*#.*$/, "")
            sub(/[[:space:]]+$/, "")
            if (length($0) == 0) next
            # split on the first ":"
            colon = index($0, ":")
            if (colon == 0) next
            key = substr($0, 1, colon - 1)
            val = substr($0, colon + 1)
            # trim both
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            if (length(key) == 0 || length(val) == 0) next
            printf "%s|%s\n", key, val
        }
    ' "$file"
}

# --- Argument parsing -------------------------------------------------------
DRY_RUN=1   # forced on for the stub
TARGET=""
AGENT="claude-code"
FEATURES=""

usage() {
    cat <<'EOF'
Usage: adopt.sh [--target=PATH] [--agent=NAME] [--features=LIST] [--dry-run] [--help]

STUB. Classifies the ADD allowlist against a target repo and reports
what adoption WOULD do. Does not modify the target. TOUCH grants,
feature install, wiki init, and overlay setup are deferred to later
iterations.

Options:
  --target=PATH      Repo to adopt into (default: current directory)
  --agent=NAME       claude-code | none | cursor (cursor: not yet supported)
  --features=LIST    Comma-separated feature names (ignored by the stub)
  --dry-run          Forced on; included for forward compatibility
  --help, -h         Show this help

See the design at
https://github.com/crcresearch/llm-wiki-memory-template/wiki/Adopt-Existing-Repo-Design
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)            usage; exit 0 ;;
        --dry-run)            DRY_RUN=1; shift ;;
        --target=*)           TARGET="${1#*=}"; shift ;;
        --target)             TARGET="${2:-}"; shift 2 ;;
        --agent=*)            AGENT="${1#*=}"; shift ;;
        --agent)              AGENT="${2:-}"; shift 2 ;;
        --features=*)         FEATURES="${1#*=}"; shift ;;
        --features)           FEATURES="${2:-}"; shift 2 ;;
        *)                    lw_die "unknown argument: $1" ;;
    esac
done

# --- Validate target --------------------------------------------------------
if [[ -z "$TARGET" ]]; then
    TARGET="$PWD"
fi

if [[ ! -d "$TARGET" ]]; then
    lw_die "target does not exist or is not a directory: $TARGET"
fi

TARGET="$(cd "$TARGET" && pwd)"

if [[ ! -d "$TARGET/.git" ]]; then
    lw_die "target is not a git repository (no .git/): $TARGET"
fi

if [[ "$TARGET" == "$TEMPLATE_ROOT" ]]; then
    lw_die "target is the template itself; adopt.sh is for OTHER repos"
fi

# --- Validate agent ---------------------------------------------------------
case "$AGENT" in
    claude-code|none) ;;
    cursor)
        lw_die "agent 'cursor' is not yet supported (see issue #6, deferred)"
        ;;
    *)
        lw_die "unknown agent '$AGENT' (expected: claude-code, none, cursor)"
        ;;
esac

# --- Resolve identity -------------------------------------------------------
PROJECT_NAME="$(lw_name_from_origin "$TARGET")"

# --- Detect 'already adopted' via composite signals -------------------------
# No single marker is decisive. The template-log file is only written by
# update-from-template.sh's first run; the wiki sub-repo lives in a separate
# remote and may not be cloned alongside the parent; any single file present
# could be coincidence. Combining independent signals — each one specific to
# the pattern in a different way — reduces both false positives (a single
# coincidental match) and false negatives (a single marker missing locally).
#
# Signals checked, all harness-agnostic (they come from the pattern itself,
# not from any specific agent overlay):
#   A: llm-wiki.md byte-identical to template
#      (strong: file unique to the pattern; byte-equal -> came from template)
#   B: wiki/agents/discipline-gates.md byte-identical to template
#      (strong: shared overlay-agnostic file from ALWAYS_FILES; present
#       regardless of which overlay the host chose, including --agent=none)
#   C: wiki/init-wiki.sh present in target
#      (moderate: specific file from the pattern; may be host-modified)
#
# Threshold: at least 2 of 3 signals must match. A single signal can be
# coincidence; two independent signals from different parts of the pattern
# make the inference reliable.
#
# Which overlay the host happens to be running (claude-code, cursor, etc.)
# is reported separately as metadata, not as a detection signal — see the
# DETECTED_OVERLAYS block below.
ADOPTION_SIGNALS=()

if [[ -f "$TARGET/llm-wiki.md" ]] \
    && cmp -s "$TEMPLATE_ROOT/llm-wiki.md" "$TARGET/llm-wiki.md"; then
    ADOPTION_SIGNALS+=("llm-wiki.md byte-identical to template")
fi
if [[ -f "$TARGET/wiki/agents/discipline-gates.md" ]] \
    && cmp -s "$TEMPLATE_ROOT/wiki/agents/discipline-gates.md" \
              "$TARGET/wiki/agents/discipline-gates.md"; then
    ADOPTION_SIGNALS+=("wiki/agents/discipline-gates.md byte-identical to template")
fi
if [[ -e "$TARGET/wiki/init-wiki.sh" ]]; then
    ADOPTION_SIGNALS+=("wiki/init-wiki.sh present")
fi

ADOPTION_THRESHOLD=2
ADOPTION_COUNT=${#ADOPTION_SIGNALS[@]}

# --- Detect which overlay (if any) is present (metadata, not a signal) ------
# Catalog approach mirroring how vulnerability scanners detect package
# managers: each overlay leaves a canonical mark in a canonical path.
# Presence here is informational; the adoption decision above does not
# depend on which overlay is configured.
DETECTED_OVERLAYS=()
if [[ -d "$TARGET/.claude" ]] || [[ -f "$TARGET/wiki/agents/claude-code/setup.sh" ]]; then
    DETECTED_OVERLAYS+=("claude-code")
fi
if [[ -d "$TARGET/.cursor" ]] || [[ -f "$TARGET/wiki/agents/cursor/setup.sh" ]]; then
    DETECTED_OVERLAYS+=("cursor")
fi

# --- Classify each path -----------------------------------------------------
# For each ADD_ALLOWLIST entry:
#   not present in target  -> ADD
#   present + identical    -> SKIP
#   present + different    -> REFUSE
ACT_ADD=()
ACT_SKIP=()
ACT_REFUSE=()
for path in "${ADD_ALLOWLIST[@]}"; do
    src="$TEMPLATE_ROOT/$path"
    dst="$TARGET/$path"
    if [[ ! -e "$src" ]]; then
        # Allowlist drift from the actual template; report so we don't
        # silently produce a misleading ADD line.
        ACT_REFUSE+=("$path  (missing in template: $src)")
        continue
    fi
    if [[ ! -e "$dst" ]]; then
        ACT_ADD+=("$path")
    elif cmp -s "$src" "$dst"; then
        ACT_SKIP+=("$path")
    else
        ACT_REFUSE+=("$path  (host-modified)")
    fi
done

# --- Classify TOUCH grants --------------------------------------------------
# Reads $TARGET/.llm-wiki-adopt-grants.yml. For each entry:
#   target unknown to template     -> TOUCH_INVALID (refuse the grant)
#   type mismatches template's op  -> TOUCH_INVALID (refuse with reason)
#   target absent in host          -> TOUCH_MISSING (grant moot)
#   otherwise                      -> TOUCH (planned, payload still deferred)
GRANTS_FILE="$TARGET/.llm-wiki-adopt-grants.yml"
ACT_TOUCH=()           # "path|type|sentinel"  (sentinel may be empty for 'merge')
ACT_TOUCH_INVALID=()   # "path  (reason)"
ACT_TOUCH_MISSING=()   # "path  (reason)"
N_GRANTS=0

if [[ -f "$GRANTS_FILE" ]]; then
    while IFS='|' read -r g_path g_type; do
        [[ -z "$g_path" ]] && continue
        N_GRANTS=$((N_GRANTS + 1))
        expected="$(known_grant_type "$g_path")"
        if [[ -z "$expected" ]]; then
            ACT_TOUCH_INVALID+=("$g_path  (unknown grant target; template has no operation for it)")
            continue
        fi
        if [[ "$g_type" != "$expected" ]]; then
            ACT_TOUCH_INVALID+=("$g_path  (type mismatch: grant says '$g_type', template knows '$expected')")
            continue
        fi
        if [[ ! -e "$TARGET/$g_path" ]]; then
            ACT_TOUCH_MISSING+=("$g_path  (granted but absent in host; grant is moot)")
            continue
        fi
        sentinel="$(known_grant_sentinel "$g_path")"
        ACT_TOUCH+=("$g_path|$g_type|$sentinel")
    done < <(parse_grants_file "$GRANTS_FILE")
fi

# --- Print report -----------------------------------------------------------
if [[ -f "$GRANTS_FILE" ]]; then
    grants_status="$(basename "$GRANTS_FILE") ($N_GRANTS grant(s) found)"
else
    grants_status="not present (host did not author one; all pre-existing files default to NEVER-TOUCH)"
fi

cat <<EOF
adopt.sh --dry-run

Target:           $TARGET
Resolved:         $PROJECT_NAME   (lw_name_from_origin)
Template:         $TEMPLATE_ROOT
Agent overlay:    $AGENT
Features:         ${FEATURES:-<none>}
Grants file:      $grants_status
EOF

if [[ "$ADOPTION_COUNT" -ge "$ADOPTION_THRESHOLD" ]]; then
    echo "Status:           already adopted ($ADOPTION_COUNT of 3 indicators matched)"
    for sig in "${ADOPTION_SIGNALS[@]}"; do
        echo "                  - $sig"
    done
    # Overlay metadata (catalog-style detection; separate from the
    # adopted/not-adopted decision above).
    if [[ ${#DETECTED_OVERLAYS[@]} -eq 0 ]]; then
        echo "                  Overlay(s) detected: none"
    else
        overlay_list="$(IFS=','; printf '%s' "${DETECTED_OVERLAYS[*]}")"
        echo "                  Overlay(s) detected: ${overlay_list//,/, }"
    fi
    # Advice: route to update-from-template AND surface the semantic gotcha.
    # Future refactor will reword 'sync list' to 'TEMPLATE_SHARED_INFRA'
    # once scripts/lib/template-manifest.sh exists; everything else stays.
    cat <<'EOF'
                  for incremental sync of template-owned files, see scripts/update-from-template.sh
                  note: that script OVERWRITES files in its sync list. The REFUSE entries
                  below mark places where overwriting would discard local changes — review
                  before using update-from-template.sh on them.
EOF
fi
echo ""

echo "ADD  (would create ${#ACT_ADD[@]} files)"
if [[ ${#ACT_ADD[@]} -eq 0 ]]; then
    echo "  (none)"
else
    for p in "${ACT_ADD[@]}"; do echo "  + $p"; done
fi
echo ""

echo "SKIP (already present, identical to template — ${#ACT_SKIP[@]} files)"
if [[ ${#ACT_SKIP[@]} -eq 0 ]]; then
    echo "  (none)"
else
    for p in "${ACT_SKIP[@]}"; do echo "  = $p"; done
fi
echo ""

echo "REFUSE (host has a different version — ${#ACT_REFUSE[@]} files)"
if [[ ${#ACT_REFUSE[@]} -eq 0 ]]; then
    echo "  (none)"
else
    for p in "${ACT_REFUSE[@]}"; do echo "  ✗ $p"; done
fi
echo ""

echo "TOUCH (host-owned, granted — ${#ACT_TOUCH[@]} files)"
if [[ ${#ACT_TOUCH[@]} -eq 0 ]]; then
    echo "  (none)"
else
    for entry in "${ACT_TOUCH[@]}"; do
        # entry = "path|type|sentinel"
        t_path="${entry%%|*}"
        rest="${entry#*|}"
        t_type="${rest%%|*}"
        t_sent="${rest#*|}"
        if [[ -n "$t_sent" ]]; then
            printf "  ~ %-32s %s (sentinel %s)\n" "$t_path" "$t_type" "$t_sent"
        else
            printf "  ~ %-32s %s\n" "$t_path" "$t_type"
        fi
    done
fi
echo ""

if [[ ${#ACT_TOUCH_INVALID[@]} -gt 0 || ${#ACT_TOUCH_MISSING[@]} -gt 0 ]]; then
    echo "GRANT WARNINGS (entries in grants file that did not produce a TOUCH)"
    for p in "${ACT_TOUCH_INVALID[@]}"; do echo "  ! $p"; done
    for p in "${ACT_TOUCH_MISSING[@]}"; do echo "  ? $p"; done
    echo ""
fi

cat <<'EOF'
NOT IMPLEMENTED YET (stub limitation, not absent from the design)
  - Actual TOUCH payloads (this stub classifies grants but does not compute or inject content)
  - Wiki sub-repo initialization (delegate to init-wiki.sh create-mode)
  - Agent overlay setup (.claude/ files via wiki/agents/claude-code/setup.sh)
  - Feature install via --features (use install_feature from scripts/lib/)
  - Apply mode (this stub is dry-run only)
  - Adoption manifest (.llm-wiki-adopt-log.md) written on apply
EOF

echo ""
echo "This is a stub. No files in $TARGET were modified."

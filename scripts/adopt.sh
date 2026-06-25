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

# --- Print report -----------------------------------------------------------
cat <<EOF
adopt.sh --dry-run

Target:           $TARGET
Resolved:         $PROJECT_NAME   (lw_name_from_origin)
Template:         $TEMPLATE_ROOT
Agent overlay:    $AGENT
Features:         ${FEATURES:-<none>}

TOUCH grants:     not implemented yet (this stub does ADD classification only)

EOF

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

cat <<'EOF'
NOT IMPLEMENTED YET (stub limitation, not absent from the design)
  - TOUCH grants (.llm-wiki-adopt-grants.yml: managed-block / append-only / merge)
  - Wiki sub-repo initialization (delegate to init-wiki.sh create-mode)
  - Agent overlay setup (.claude/ files via wiki/agents/claude-code/setup.sh)
  - Feature install via --features (use install_feature from scripts/lib/)
  - Apply mode (this stub is dry-run only)
  - Adoption manifest (.llm-wiki-adopt-log.md) written on apply
EOF

echo ""
echo "This is a stub. No files in $TARGET were modified."

#!/usr/bin/env bash
# Patch: stage a template copy and a virgin host, then adopt into the host.
#
# The assertions prove the ADOPTED HOST's own sync tooling works — the
# tooling adopt itself installs (#74: update-from-template.sh and
# check-template-version.sh source scripts/lib/template-manifest.sh from
# the HOST tree, so adopt must ship the manifest too) — and that the
# host's wiki carries the stamped Edge-Types page (#75: init-wiki stamps
# wiki/*.md.template from the HOST's wiki/ under nullglob, so a template
# file adopt never shipped is a silent no-op).
#
# The template side is staged via clone_template into the sandbox (a real
# git repo with one commit on a detectable default branch) rather than
# pointing at this checkout directly: CI checkouts are detached-HEAD and
# PR runs may lack a local main, which would break the host-side
# `git fetch template <branch>` for reasons unrelated to #74.
#
# Inputs:  SANDBOX env var. lib/template.sh's clone_template.
# Effects: $SANDBOX/adopted-host-sync/{template,host}; host adopted with
#          --agent=claude-code. Declines cleanly (nothing staged) when no
#          template source is available (offline, or derived checkout per
#          issue #15).
#
# Idempotent.

set -uo pipefail

HARNESS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/template.sh
source "$HARNESS_LIB/template.sh"

STAGE="$SANDBOX/adopted-host-sync"
T="$STAGE/template"
H="$STAGE/host"
mkdir -p "$STAGE"

if [ -d "$T" ]; then
    echo "  adopted-host-sync template already staged at $T (idempotent re-run)."
elif ! clone_template "$T"; then
    echo "  adopted-host-sync assertions will skip: no template clone available." >&2
    rm -rf "$STAGE"
    exit 0
fi

if [ ! -d "$H/.git" ]; then
    git init -q "$H"
    git -C "$H" remote add origin "https://github.com/acme/sync-host.git"
    echo "# Sync Host" > "$H/README.md"
    git -C "$H" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H" -c user.email=t@x.invalid -c user.name=t commit -qm "initial"
fi

if [ ! -f "$H/llm-wiki.md" ]; then
    rc=0
    bash "$T/scripts/adopt.sh" --target="$H" --apply --agent=claude-code \
        >/tmp/adopted-host-sync.log 2>&1 || rc=$?
    # rc sidecar outside the tree; assertions.sh asserts rc == 0.
    echo "$rc" > "$H.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed (rc=$rc); the exit-status assertion will fail." >&2
        sed 's/^/    /' /tmp/adopted-host-sync.log >&2
    fi
fi

# --- H2: legacy host — adopted BEFORE the manifest shipped itself (#74) -----
# Simulated by adopting normally, then deleting the artifacts a pre-fix
# adopt never delivered: the manifest and the Edge-Types template + page.
# assertions.sh runs the HOST's own update-from-template.sh (apply mode)
# and requires it to self-heal via the bootstrap instead of dying at its
# source line.
H2="$STAGE/legacy-host"
if [ ! -d "$H2/.git" ]; then
    git init -q "$H2"
    git -C "$H2" remote add origin "https://github.com/acme/legacy-host.git"
    echo "# Legacy Host" > "$H2/README.md"
    git -C "$H2" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H2" -c user.email=t@x.invalid -c user.name=t commit -qm "initial"
    rc=0
    bash "$T/scripts/adopt.sh" --target="$H2" --apply --agent=claude-code \
        >/tmp/adopted-host-sync-h2.log 2>&1 || rc=$?
    echo "$rc" > "$H2.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed on legacy host (rc=$rc)." >&2
        sed 's/^/    /' /tmp/adopted-host-sync-h2.log >&2
    fi
    rm -f "$H2/scripts/lib/template-manifest.sh" \
          "$H2/wiki/Edge-Types.md.template" \
          "$H2/wiki/legacy-host.wiki/Edge-Types.md"
fi

# --- H3: host whose wiki sub-repo ALREADY exists at adopt time (#75) --------
# adopt's init-wiki dispatch short-circuits on wiki/<repo>.wiki/.git, so
# stamping must happen via the already-present branch. The pre-existing
# wiki carries sentinel content that adopt must NOT touch. The committed
# .gitignore rule keeps the wiki sub-repo out of git status so adopt's
# clean-tree guard passes (the same rule adopt's own grant installs).
H3="$STAGE/prewiki-host"
if [ ! -d "$H3/.git" ]; then
    git init -q "$H3"
    git -C "$H3" remote add origin "https://github.com/acme/prewiki-host.git"
    echo "# Prewiki Host" > "$H3/README.md"
    printf 'wiki/*.wiki/\n' > "$H3/.gitignore"
    mkdir -p "$H3/wiki/prewiki-host.wiki"
    git init -q "$H3/wiki/prewiki-host.wiki"
    printf '# SCHEMA\n\nPRE_EXISTING_SCHEMA_SENTINEL\n' \
        > "$H3/wiki/prewiki-host.wiki/SCHEMA_prewiki-host.md"
    printf '# Home\n\nPRE_EXISTING_HOME_SENTINEL\n' \
        > "$H3/wiki/prewiki-host.wiki/Home_prewiki-host.md"
    git -C "$H3" -c user.email=t@x.invalid -c user.name=t add -A
    git -C "$H3" -c user.email=t@x.invalid -c user.name=t commit -qm "initial"
    rc=0
    bash "$T/scripts/adopt.sh" --target="$H3" --apply --agent=claude-code \
        >/tmp/adopted-host-sync-h3.log 2>&1 || rc=$?
    echo "$rc" > "$H3.adopt-rc"
    if [ "$rc" -ne 0 ]; then
        echo "  WARN: adopt --apply failed on prewiki host (rc=$rc)." >&2
        sed 's/^/    /' /tmp/adopted-host-sync-h3.log >&2
    fi
fi

echo "  adopted-host-sync patch applied: template at $T, hosts at $H, $H2, $H3."

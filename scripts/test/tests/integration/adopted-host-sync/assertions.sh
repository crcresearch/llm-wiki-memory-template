#!/usr/bin/env bash
# Assertions: an adopted host's OWN sync tooling must work (#74) and its
# wiki must carry the stamped Edge-Types page (#75).
#
# #74: update-from-template.sh and check-template-version.sh source
# scripts/lib/template-manifest.sh from the HOST tree. If adopt does not
# ship the manifest itself, both die at their source line — the exact
# failure this fixture pins. The template remote for the host-side runs
# is the sandbox-staged template repo (hermetic; no network).
#
# #75: init-wiki stamps wiki/*.md.template from the HOST's wiki/ dir under
# nullglob, so a missing Edge-Types.md.template is a silent no-op and the
# stamped SCHEMA's [Edge-Types] links all dangle.

STAGE="$SANDBOX/adopted-host-sync"
T="$STAGE/template"
H="$STAGE/host"

# patch.sh declines (removes $STAGE) when no template source is available
# (offline, or derived checkout per issue #15).
if [ ! -d "$H" ]; then
    skip "adopted-host-sync assertions" "no template clone available (offline, or run inside a derived project)"
    return 0 2>/dev/null || true
fi

assert "adopt --apply exited 0" \
    "[ \"\$(cat '$H.adopt-rc' 2>/dev/null)\" = '0' ]"

# --- #74: the manifest ships, and the host-side sync tooling runs -----------
assert "host has scripts/lib/template-manifest.sh" \
    "[ -f '$H/scripts/lib/template-manifest.sh' ]"

update_rc=0
( cd "$H" && ./scripts/update-from-template.sh --dry-run --template-url="$T" ) \
    > "$STAGE/update-dry-run.out" 2>&1 || update_rc=$?
assert_eq "host update-from-template.sh --dry-run exit status" "0" "$update_rc"
# The full banner line only prints after the manifest sourced and the
# template fetch succeeded; the pre-fix crash output does not contain it.
assert "host update dry-run printed its report banner" \
    "grep -qF '================ update-from-template ================' '$STAGE/update-dry-run.out'"

check_rc=0
( cd "$H" && ./scripts/check-template-version.sh --template-url="$T" ) \
    > "$STAGE/check-version.out" 2>&1 || check_rc=$?
# rc 0 = in sync, rc 1 = drift: both are completed runs. The pre-fix
# source crash also exits 1, so the banner assertion below is the one
# that separates "reported drift" from "died before reporting".
assert "host check-template-version completed (rc <= 1)" \
    "[ '$check_rc' -le 1 ]"
assert "host check-template-version printed its report banner" \
    "grep -qF '================ check-template-version ================' '$STAGE/check-version.out'"

# --- #75: Edge-Types template ships and gets stamped into the wiki ----------
assert "host received wiki/Edge-Types.md.template" \
    "[ -f '$H/wiki/Edge-Types.md.template' ]"
EDGE="$H/wiki/sync-host.wiki/Edge-Types.md"
assert "adopted wiki has Edge-Types.md (stamped by init-wiki)" \
    "[ -f '$EDGE' ]"
assert "stamped Edge-Types.md has the repo name substituted" \
    "grep -qF 'sync-host' '$EDGE'"
assert "stamped Edge-Types.md has no {{REPO_NAME}} placeholder left" \
    "! grep -qF '{{REPO_NAME}}' '$EDGE'"

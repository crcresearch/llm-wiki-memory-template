#!/usr/bin/env bash
#
# text.sh — portable, idempotent text patching.
#
# Two fixes from the audit live here as single canonical implementations:
#   - paired HTML-comment sentinels (matching install-feature.sh's
#     <!-- feature:NAME --> convention) replace fragile grep-on-prose-
#     heading idempotency, which false-negatives on wording drift
#     (duplicate injection) and false-positives on substring matches (skip);
#   - the BSD-safe awk-via-tempfile injector, which claude-code/setup.sh
#     has but cursor/setup.sh lacks (cursor silently no-ops on macOS).

# In-place sed that works on GNU and BSD sed alike.
lw_sed_inplace() {
  local expr="$1" file="$2"
  sed -i.bak "$expr" "$file" && rm -f "$file.bak"
}

# Inject CONTENT once, wrapped in <!-- lw:KEY --> ... <!-- /lw:KEY -->.
# No-op (return 1) if the opening sentinel is already present, so
# idempotency is independent of how CONTENT is worded. If BEFORE is given
# and found, insert above the first matching line; otherwise append.
lw_inject_block() {
  local file="$1" key="$2" content="$3" before="${4:-}"
  local open="<!-- lw:$key -->" close="<!-- /lw:$key -->"
  grep -qF "$open" "$file" 2>/dev/null && return 1
  local block
  block="$(printf '%s\n%s\n%s' "$open" "$content" "$close")"
  if [[ -n "$before" ]] && grep -qF "$before" "$file" 2>/dev/null; then
    lw_insert_before "$file" "$before" "$block"
  else
    printf '\n%s\n' "$block" >> "$file"
  fi
  return 0
}

# TODO(update-in-place): replace the body between an existing paired
# sentinel. Implement when the first consumer needs update (vs first-run
# inject) semantics; not needed for the initial migration.
# lw_replace_block() { ... }

# Insert a multi-line BLOCK before the first line containing NEEDLE.
# The block is handed to awk via a tempfile + getline rather than -v
# because BSD awk (macOS) rejects newlines in -v assignments and silently
# emits empty output. Both overlay setup scripts route their CLAUDE.md
# snippet injection through this one helper so the BSD-safe behavior lives
# in a single place (cursor's old inline `awk -v snippet=...` no-opped on
# macOS).
lw_insert_before() {
  local file="$1" needle="$2" block="$3" tmp blockfile
  tmp="$(mktemp)"; blockfile="$(mktemp)"
  printf '%s\n' "$block" > "$blockfile"
  awk -v needle="$needle" -v bf="$blockfile" '
    index($0, needle) && !done {
      while ((getline line < bf) > 0) print line
      close(bf); print ""; done = 1
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  rm -f "$blockfile"
}

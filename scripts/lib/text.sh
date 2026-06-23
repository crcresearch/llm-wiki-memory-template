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

# Replace the body between an existing <!-- lw:KEY --> / <!-- /lw:KEY --> pair
# with CONTENT, leaving the sentinels and all surrounding text intact. No-op
# (return 1) when the opening sentinel is absent, so a caller can fall back to
# lw_inject_block for the first-run case. This is the update-in-place
# counterpart to lw_inject_block; the overlays deliberately do NOT call it on
# every run (they inject once, to preserve any local edits a user made inside
# the block), but it is the canonical primitive for an explicit content refresh.
lw_replace_block() {
  local file="$1" key="$2" content="$3"
  local open="<!-- lw:$key -->" close="<!-- /lw:$key -->"
  grep -qF "$open" "$file" 2>/dev/null || return 1
  local tmp blockfile; tmp="$(mktemp)"; blockfile="$(mktemp)"
  printf '%s\n' "$content" > "$blockfile"
  # awk var is endm, not 'close' ('close' is an awk builtin and gawk rejects
  # it as a variable name); the close(bf) call below is the real builtin.
  awk -v open="$open" -v endm="$close" -v bf="$blockfile" '
    $0 == open { print; while ((getline line < bf) > 0) print line; close(bf); skip=1; next }
    $0 == endm { skip=0 }
    !skip      { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  rm -f "$blockfile"
  return 0
}

# Wrap a pre-sentinel prose section in paired <!-- lw:KEY --> sentinels, in
# place, preserving its content. This is the one-time migration path for
# projects created before the sentinel format: their CLAUDE.md carries a bare
# "### Heading" section, and without wrapping, a sentinel-based lw_inject_block
# would not recognize it and would inject a duplicate. No-op (return 1) when
# the sentinel already exists (already migrated) or HEADING is absent (nothing
# to wrap). The section runs from the exact HEADING line to just before the
# next markdown heading (^#+ space) or EOF, so any local edits inside it are
# preserved (D4: wrap-in-place, not replace).
lw_wrap_section() {
  local file="$1" key="$2" heading="$3"
  local open="<!-- lw:$key -->" close="<!-- /lw:$key -->"
  grep -qF "$open"     "$file" 2>/dev/null && return 1
  grep -qxF "$heading" "$file" 2>/dev/null || return 1
  local tmp; tmp="$(mktemp)"
  # awk var is endm, not 'close' (an awk builtin gawk rejects as a var name).
  awk -v heading="$heading" -v open="$open" -v endm="$close" '
    !done && $0 == heading { print open; print; inside=1; done=1; next }
    inside && /^#+ /        { print endm; inside=0 }
    { print }
    END { if (inside) print endm }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  return 0
}

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

# Insert a multi-line BLOCK on the line(s) immediately after the first line
# containing NEEDLE. The sed-free counterpart to appending after a matched
# line: `sed 'Na\<newline>text'` is rejected by BSD/macOS sed (it silently
# no-ops), so anything that needs to append under a heading goes through this
# instead. Same blockfile + getline mechanism as lw_insert_before, so it is
# BSD-safe for multi-line blocks too. No trailing blank line is added, which
# is what list registration (e.g. WIKI-INDEX entries) wants.
lw_append_after() {
  local file="$1" needle="$2" block="$3" tmp blockfile
  tmp="$(mktemp)"; blockfile="$(mktemp)"
  printf '%s\n' "$block" > "$blockfile"
  awk -v needle="$needle" -v bf="$blockfile" '
    { print }
    index($0, needle) && !done {
      while ((getline line < bf) > 0) print line
      close(bf); done = 1
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  rm -f "$blockfile"
}

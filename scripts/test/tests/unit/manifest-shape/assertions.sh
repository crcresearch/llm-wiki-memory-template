#!/usr/bin/env bash
# Assertions for scripts/lib/template-manifest.sh.
#
# The manifest declares which files the template owns and how each is
# synced. The script consumers (update-from-template.sh, check-template-
# version.sh, adopt.sh) trust the contract; these assertions enforce it.
#
# Every manifest call goes through lw_mcall: a subshell that sources the
# manifest in isolation, so a typo in the manifest cannot poison the
# runner's environment.

ROOT="$SANDBOX/manifest-shape"
REPO_ROOT_LIB="$(cd "$HERE/../.." && pwd)"
LW_MANIFEST="$REPO_ROOT_LIB/scripts/lib/template-manifest.sh"

# Template-checkout guard: the tree invariants below (every SUBSTITUTE
# entry still contains {{REPO_NAME}}, every overlay entry exists on disk)
# hold only in the template repo. This harness ships to derived projects
# via "Use this template", where instantiate has already substituted the
# placeholders and pruned the unused overlays — there the invariants are
# legitimately false (observed: 12 spurious fails in a derived project's
# CI). Same discriminator as clone_template's issue-#15 guard: only the
# template checkout carries CLAUDE.md.template.
if [ ! -f "$REPO_ROOT_LIB/CLAUDE.md.template" ]; then
    skip "manifest-shape assertions" "not a template checkout (derived project; manifest tree-invariants do not apply)"
    return 0 2>/dev/null || true
fi

# Subshell sourcer; stdout is the eval result, exit status is the call's.
# shellcheck source=/dev/null
lw_mcall() { ( set -uo pipefail; source "$LW_MANIFEST"; eval "$1" ); }

# --- Existence + parseability ----------------------------------------------
assert "template-manifest.sh exists"          "[ -f '$LW_MANIFEST' ]"
assert "template-manifest.sh passes bash -n"  "bash -n '$LW_MANIFEST'"
assert "template-manifest.sh sources cleanly" "lw_mcall true"

# --- Arrays are non-empty --------------------------------------------------
for _arr in TEMPLATE_SHARED_INFRA TEMPLATE_OVERLAY_CLAUDE TEMPLATE_OVERLAY_CURSOR \
            TEMPLATE_SUBSTITUTE_FILES TEMPLATE_HOST_OWNED TEMPLATE_ONE_SHOT; do
    assert_eq "$_arr is non-empty" "1" "$(lw_mcall "[ \${#$_arr[@]} -gt 0 ] && echo 1 || echo 0")"
done

# --- Idempotent source guard -----------------------------------------------
# Sourcing twice in the same shell must not duplicate work or rebind state.
assert_eq "double-source preserves shared-infra count" \
    "$(lw_mcall 'echo "${#TEMPLATE_SHARED_INFRA[@]}"')" \
    "$(lw_mcall 'source "$LW_MANIFEST"; echo "${#TEMPLATE_SHARED_INFRA[@]}"' 2>/dev/null || true)"

# --- HOST_OWNED entries have well-formed grants ----------------------------
# Each "path|type" must split into two non-empty halves and resolve to a
# known_grant_type (managed-block, append-only, merge) recognised by the
# accessor.
HOST_OWNED_ENTRIES="$(lw_mcall 'printf "%s\n" "${TEMPLATE_HOST_OWNED[@]}"')"
while IFS= read -r _entry; do
    [[ -n "$_entry" ]] || continue
    _path="${_entry%%|*}"
    _type="${_entry##*|}"
    assert "HOST_OWNED entry has non-empty path  ($_entry)"  "[ -n '$_path' ]"
    assert "HOST_OWNED entry has non-empty type  ($_entry)"  "[ -n '$_type' ]"
    assert "HOST_OWNED entry has known op type   ($_entry)" \
        "case '$_type' in managed-block|append-only|merge) true ;; *) false ;; esac"
    _resolved="$(lw_mcall "lw_manifest_known_grant_type '$_path'")"
    assert_eq "lw_manifest_known_grant_type('$_path')" "$_type" "$_resolved"
done <<< "$HOST_OWNED_ENTRIES"

# --- HOST_OWNED is disjoint from sync arrays -------------------------------
# A path that is host-owned must not also appear in any sync array; if it
# did, update-from-template would overwrite host content the host is meant
# to own.
for _arr in TEMPLATE_SHARED_INFRA TEMPLATE_OVERLAY_CLAUDE TEMPLATE_OVERLAY_CURSOR; do
    _overlap="$(lw_mcall "
        for ho in \"\${TEMPLATE_HOST_OWNED[@]}\"; do
            p=\"\${ho%%|*}\"
            for s in \"\${$_arr[@]}\"; do
                [[ \"\$s\" == \"\$p\" ]] && echo \"\$p\"
            done
        done")"
    assert "$_arr ∩ HOST_OWNED is empty" "[ -z \"$_overlap\" ]"
done

# --- TEMPLATE_SUBSTITUTE_FILES ⊆ (SHARED_INFRA ∪ OVERLAY_CLAUDE ∪ OVERLAY_CURSOR) ---
# A substitute entry that isn't synced anywhere is dead code; flag it.
_orphan_substitutes="$(lw_mcall "
    for s in \"\${TEMPLATE_SUBSTITUTE_FILES[@]}\"; do
        found=0
        for f in \"\${TEMPLATE_SHARED_INFRA[@]}\" \"\${TEMPLATE_OVERLAY_CLAUDE[@]}\" \"\${TEMPLATE_OVERLAY_CURSOR[@]}\"; do
            [[ \"\$f\" == \"\$s\" ]] && { found=1; break; }
        done
        [[ \$found -eq 0 ]] && echo \"\$s\"
    done")"
assert "TEMPLATE_SUBSTITUTE_FILES ⊆ sync arrays (no orphans)" "[ -z \"$_orphan_substitutes\" ]"

# --- Every TEMPLATE_SUBSTITUTE_FILES entry actually contains {{REPO_NAME}} -
# This is the load-bearing check that catches the inverse drift: someone
# adds a path to SUBSTITUTE_FILES that doesn't have the marker. Skip if the
# template root copy is missing (would be a separate failure).
while IFS= read -r _s; do
    [[ -n "$_s" ]] || continue
    if [[ -f "$REPO_ROOT_LIB/$_s" ]]; then
        assert "SUBSTITUTE entry contains {{REPO_NAME}}: $_s" \
            "grep -qF '{{REPO_NAME}}' '$REPO_ROOT_LIB/$_s'"
    else
        skip "SUBSTITUTE entry presence in template tree: $_s" "template file not present in this checkout"
    fi
done < <(lw_mcall 'printf "%s\n" "${TEMPLATE_SUBSTITUTE_FILES[@]}"')

# --- Every manifest path actually exists in the template tree --------------
# Catches the drift the previous PR cycle suffered from twice (overlay
# template added, manifest forgotten).
for _arr in TEMPLATE_SHARED_INFRA TEMPLATE_OVERLAY_CLAUDE TEMPLATE_OVERLAY_CURSOR; do
    while IFS= read -r _path; do
        [[ -n "$_path" ]] || continue
        assert "$_arr entry exists in template tree: $_path" \
            "[ -e '$REPO_ROOT_LIB/$_path' ]"
    done < <(lw_mcall "printf '%s\n' \"\${$_arr[@]}\"")
done

# --- Accessor: lw_manifest_needs_substitution ------------------------------
# Truth-table check: the first SUBSTITUTE entry is in, llm-wiki.md is not.
_first_sub="$(lw_mcall 'printf "%s\n" "${TEMPLATE_SUBSTITUTE_FILES[0]}"')"
lw_mcall "lw_manifest_needs_substitution '$_first_sub'"; RC=$?
assert "needs_substitution returns 0 for a SUBSTITUTE entry ($_first_sub)" "[ $RC -eq 0 ]"
lw_mcall "lw_manifest_needs_substitution 'llm-wiki.md'"; RC=$?
assert "needs_substitution returns non-zero for a non-SUBSTITUTE path"      "[ $RC -ne 0 ]"

# --- Accessor: lw_manifest_assemble_active_files ---------------------------
# Counts (used in three assertions below).
N_SHARED="$(lw_mcall 'echo "${#TEMPLATE_SHARED_INFRA[@]}"')"
N_CLAUDE="$(lw_mcall 'echo "${#TEMPLATE_OVERLAY_CLAUDE[@]}"')"
N_CURSOR="$(lw_mcall 'echo "${#TEMPLATE_OVERLAY_CURSOR[@]}"')"
N_SHARED_PLUS_CLAUDE="$((N_SHARED + N_CLAUDE))"
N_SHARED_PLUS_CURSOR="$((N_SHARED + N_CURSOR))"

# Mode A: agent=claude-code, repo_root empty (adopt's call shape).
N_A="$(lw_mcall "lw_manifest_assemble_active_files '' 'claude-code'" | wc -l | tr -d ' ')"
assert_eq "assemble(agent=claude-code) = SHARED + OVERLAY_CLAUDE" "$N_SHARED_PLUS_CLAUDE" "$N_A"

# Mode B: agent=cursor, repo_root empty.
N_B="$(lw_mcall "lw_manifest_assemble_active_files '' 'cursor'" | wc -l | tr -d ' ')"
assert_eq "assemble(agent=cursor) = SHARED + OVERLAY_CURSOR" "$N_SHARED_PLUS_CURSOR" "$N_B"

# Mode C: agent=none (literally any non-matching string + empty repo_root)
# yields just SHARED. Adopt's --agent=none also hits this branch.
N_C="$(lw_mcall "lw_manifest_assemble_active_files '' 'none'" | wc -l | tr -d ' ')"
assert_eq "assemble(agent=none) = SHARED only"                "$N_SHARED"              "$N_C"

# Mode D: detection on host with .claude/ (update/check's call shape).
N_D="$(lw_mcall "lw_manifest_assemble_active_files '$ROOT/host-with-claude' ''" | wc -l | tr -d ' ')"
assert_eq "assemble(detect) host-with-claude/.claude  = SHARED + OVERLAY_CLAUDE" \
    "$N_SHARED_PLUS_CLAUDE" "$N_D"

# Mode E: detection on host with .cursor/.
N_E="$(lw_mcall "lw_manifest_assemble_active_files '$ROOT/host-with-cursor' ''" | wc -l | tr -d ' ')"
assert_eq "assemble(detect) host-with-cursor/.cursor  = SHARED + OVERLAY_CURSOR" \
    "$N_SHARED_PLUS_CURSOR" "$N_E"

# Mode F: detection on a bare host with neither overlay = SHARED only.
N_F="$(lw_mcall "lw_manifest_assemble_active_files '$ROOT/host-bare' ''" | wc -l | tr -d ' ')"
assert_eq "assemble(detect) host-bare                 = SHARED only" "$N_SHARED" "$N_F"

# --- Accessor: lw_manifest_known_grant_sentinel + _payload -----------------
# .gitignore returns "lw:wiki-rules" and a payload mentioning wiki/*.wiki/.
assert_eq "known_grant_sentinel(.gitignore) = lw:wiki-rules" "lw:wiki-rules" \
    "$(lw_mcall "lw_manifest_known_grant_sentinel '.gitignore'")"
assert "known_grant_payload(.gitignore) mentions wiki/*.wiki/" \
    "lw_mcall \"lw_manifest_known_grant_payload '.gitignore'\" | grep -qF 'wiki/*.wiki/'"
assert_eq "known_grant_sentinel(CLAUDE.md) is empty (managed-block delegates to overlay)" "" \
    "$(lw_mcall "lw_manifest_known_grant_sentinel 'CLAUDE.md'")"
assert_eq "known_grant_sentinel(unknown path) is empty" "" \
    "$(lw_mcall "lw_manifest_known_grant_sentinel 'random/path.txt'")"

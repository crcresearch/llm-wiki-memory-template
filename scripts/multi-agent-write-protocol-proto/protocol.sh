#!/usr/bin/env bash
# Multi-agent wiki write protocol: deterministic shell implementation.
#
# Encodes the protocol from the template wiki page
# Multi-Agent-Write-Protocol.md: each agent writes via its own contribution
# branch, attempts a merge against origin/main, and either pushes cleanly
# or retries with a deterministic resolution policy.
#
# The "semantic resolution" step is replaced with a deterministic policy
# function (passed in by the caller) so the protocol can be tested without
# an LLM in the loop. Real implementations would replace the policy with
# LLM-based reasoning over the conflict.
#
# Callers should source this file then call agent_write.
#
# Globals contributed: none. All state is local-to-function.

# Default retry cap. AGENT_MAX_RETRIES is the number of *retries* allowed
# after the first attempt; total attempts = AGENT_MAX_RETRIES + 1.
# E.g. AGENT_MAX_RETRIES=3 → up to 4 attempts total before halting.
AGENT_MAX_RETRIES="${AGENT_MAX_RETRIES:-3}"

# Set up the union-merge driver for index_* and log_* files. Call once
# per wiki clone (per agent). Without this, the agent will mis-classify
# index/log additions as semantic conflicts.
protocol_install_union_merge() {
    local wiki_dir="$1"
    local attrs="$wiki_dir/.gitattributes"
    if ! grep -qE '^(index|log)_.*merge=union' "$attrs" 2>/dev/null; then
        cat >> "$attrs" <<'EOF'
index_*.md  merge=union
log_*.md    merge=union
EOF
        git -C "$wiki_dir" add .gitattributes
        git -C "$wiki_dir" commit -m "Configure union merge for index/log files" --quiet
    fi
}

# Make an agent-specific working branch name. Avoids collisions when two
# agents act in the same process (e.g., the test driver) by including
# microsecond-resolution time.
protocol_branch_name() {
    local handle="$1"
    # On macOS, date %N returns literal "N"; use /tmp seq counter as fallback
    local ts="$(date +%s)"
    local seq_file="/tmp/.protocol_branch_seq.$$"
    local n
    n="$(( $(cat "$seq_file" 2>/dev/null || echo 0) + 1 ))"
    echo "$n" > "$seq_file"
    echo "agent/${handle}/${ts}-${n}"
}

# Apply changes via the caller-supplied function. The function is called
# with the wiki directory as its first argument and is expected to write
# files and `git add` them. The function should NOT commit; this function
# commits on its behalf.
#
# Args: wiki_dir, changes_fn_name, commit_msg
protocol_make_changes() {
    local wiki_dir="$1"
    local changes_fn="$2"
    local msg="$3"
    "$changes_fn" "$wiki_dir"
    if git -C "$wiki_dir" diff --cached --quiet; then
        # Nothing staged. The changes function may have decided there's
        # nothing to do (e.g., after a "drop" resolution).
        return 1
    fi
    git -C "$wiki_dir" commit -m "$msg" --quiet
    return 0
}

# Classify a conflict file. Echoes one of: union, semantic, none.
#  - union: index_*.md or log_*.md (auto-merged via .gitattributes, but if
#    we hit this here it means the driver wasn't installed; treat as a
#    bug, but also union-merge it ourselves as a fallback).
#  - semantic: anything else with conflict markers.
protocol_classify_conflict() {
    local file="$1"
    case "$(basename "$file")" in
        index_*.md|log_*.md) echo "union" ;;
        *) echo "semantic" ;;
    esac
}

# Get the list of files with merge conflicts, one per line.
protocol_conflict_files() {
    local wiki_dir="$1"
    git -C "$wiki_dir" diff --name-only --diff-filter=U
}

# Fall-back union merge: combine both sides of every conflict block.
# Used when .gitattributes union driver didn't apply (e.g., on a non-
# index/log file the caller marks as union-mergeable). Keeps both sides
# in commit order: <<< side first, then ===, then >>> side.
protocol_apply_union_merge() {
    local file="$1"
    # Remove the conflict markers; keep all content from both sides.
    # The default git merge already wrote both versions interleaved; we
    # just strip the markers.
    sed -E -i.bak '/^(<<<<<<< |=======|>>>>>>> )/d' "$file"
    rm -f "$file.bak"
}

# Steps 1-2 of the protocol: fetch, branch from origin/main, apply changes,
# commit. Leaves the working branch checked out. Echoes the branch name on
# stdout so the caller can pair this with a later agent_publish.
#
# Args: wiki_dir, handle, changes_fn, commit_msg.
# Returns 0 on success (a commit was made), 1 if no changes were produced.
agent_prepare() {
    local wiki_dir="$1"
    local handle="$2"
    local changes_fn="$3"
    local commit_msg="$4"

    protocol_install_union_merge "$wiki_dir"
    git -C "$wiki_dir" fetch origin --quiet
    local branch
    branch="$(protocol_branch_name "$handle")"
    git -C "$wiki_dir" checkout -B "$branch" origin/main --quiet

    if ! protocol_make_changes "$wiki_dir" "$changes_fn" "$commit_msg"; then
        echo "  [$handle] no changes to commit" >&2
        return 1
    fi
    echo "$branch"
    return 0
}

# Steps 3-6 of the protocol: merge origin/main into the currently-checked-
# out working branch, resolve conflicts (mechanical for index/log, semantic
# otherwise), push to origin/main, retry on rejection up to AGENT_MAX_RETRIES.
#
# Args: wiki_dir, handle, resolve_fn.
# Returns: 0 on success, 2 on retry cap hit, 3 on internal protocol bug.
agent_publish() {
    local wiki_dir="$1"
    local handle="$2"
    local resolve_fn="$3"

    # Total attempts = AGENT_MAX_RETRIES + 1 (first attempt + retries).
    local attempt=0
    local max_attempts=$((AGENT_MAX_RETRIES + 1))
    while true; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt "$max_attempts" ]; then
            echo "  [$handle] hit retry cap (max attempts $max_attempts); halting" >&2
            return 2
        fi

        git -C "$wiki_dir" fetch origin --quiet

        # If origin/main is at the same commit our branch's first parent is,
        # nothing has moved; push directly. Otherwise we need to merge.
        local origin_main_sha
        origin_main_sha="$(git -C "$wiki_dir" rev-parse origin/main)"
        local merge_base
        merge_base="$(git -C "$wiki_dir" merge-base HEAD origin/main)"

        if [ "$origin_main_sha" = "$merge_base" ]; then
            # We are ahead of (or aligned with) origin/main. Try to push.
            if git -C "$wiki_dir" push origin "HEAD:main" --quiet 2>/dev/null; then
                echo "  [$handle] pushed clean on attempt $attempt"
                return 0
            else
                echo "  [$handle] push rejected (race); will refetch and retry" >&2
                continue
            fi
        fi

        # origin/main has moved. Attempt a merge.
        if git -C "$wiki_dir" merge --no-commit --no-ff origin/main --quiet 2>/dev/null; then
            # Merge applied cleanly without needing a commit yet; commit and push.
            git -C "$wiki_dir" commit -m "Merge origin/main into agent branch" --quiet
            if git -C "$wiki_dir" push origin "HEAD:main" --quiet 2>/dev/null; then
                echo "  [$handle] pushed after clean merge on attempt $attempt"
                return 0
            else
                echo "  [$handle] push rejected after clean merge (race); will refetch and retry" >&2
                continue
            fi
        fi

        # Conflict. Classify and resolve.
        local conflicted
        conflicted="$(protocol_conflict_files "$wiki_dir")"
        if [ -z "$conflicted" ]; then
            echo "  [$handle] merge failed but no conflicted files? bug; aborting" >&2
            git -C "$wiki_dir" merge --abort
            return 3
        fi

        local needs_semantic=0
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            local class
            class="$(protocol_classify_conflict "$file")"
            case "$class" in
                union)
                    protocol_apply_union_merge "$wiki_dir/$file"
                    git -C "$wiki_dir" add "$file"
                    echo "  [$handle]   union-merged $file"
                    ;;
                semantic)
                    needs_semantic=1
                    "$resolve_fn" "$wiki_dir" "$file"
                    if [ ! -f "$wiki_dir/$file" ]; then
                        # Resolver chose to drop the file. Stage the deletion.
                        git -C "$wiki_dir" rm -f "$file" --quiet
                    else
                        git -C "$wiki_dir" add "$file"
                    fi
                    echo "  [$handle]   semantic-resolved $file"
                    ;;
            esac
        done <<< "$conflicted"

        git -C "$wiki_dir" commit -m "Resolve merge with origin/main into agent branch" --quiet

        if git -C "$wiki_dir" push origin "HEAD:main" --quiet 2>/dev/null; then
            echo "  [$handle] pushed after resolved merge on attempt $attempt"
            return 0
        else
            echo "  [$handle] push rejected after resolved merge (race); will refetch and retry" >&2
            continue
        fi
    done
}

# Convenience: prepare then publish. The original "all in one" entry point.
# Most scenarios use this; scenarios that need to interleave prepare/publish
# across multiple agents call agent_prepare + agent_publish directly.
#
# Args: wiki_dir, handle, changes_fn, resolve_fn, commit_msg.
agent_write() {
    local wiki_dir="$1"
    local handle="$2"
    local changes_fn="$3"
    local resolve_fn="$4"
    local commit_msg="$5"
    if ! agent_prepare "$wiki_dir" "$handle" "$changes_fn" "$commit_msg" >/dev/null; then
        return 0
    fi
    agent_publish "$wiki_dir" "$handle" "$resolve_fn"
}

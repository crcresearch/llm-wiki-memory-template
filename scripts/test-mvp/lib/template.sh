#!/usr/bin/env bash
# Template-clone helper for the MVP test harness.
#
# clone_template clones (or copies from local) the real template repo. Used
# by smoke tests that exercise the template's actual bootstrap, including
# init-wiki.sh in create and update modes.
#
# Two env vars control template resolution, in order of precedence:
#   MVP_TEMPLATE_LOCAL=/path/to/clone  use a local clone (offline, fast)
#   MVP_TEMPLATE_REPO=<url>            clone from this URL (default: the
#                                       chrissweet fork of the template)

DEFAULT_TEMPLATE_REPO="https://github.com/chrissweet/llm-wiki-memory-template.git"

# Clone the real template into TARGET. Prefers MVP_TEMPLATE_LOCAL if set
# (offline mode), falls back to MVP_TEMPLATE_REPO (or DEFAULT_TEMPLATE_REPO).
# Returns 0 on success, 1 if both modes fail (e.g. no network and no local).
clone_template() {
    local target="$1"
    local repo="${MVP_TEMPLATE_REPO:-$DEFAULT_TEMPLATE_REPO}"
    local local_clone="${MVP_TEMPLATE_LOCAL:-}"

    if [ -n "$local_clone" ] && [ -d "$local_clone" ]; then
        # Local-clone mode: copy the working tree (preserving .git would
        # confuse instantiate.sh which expects to commit fresh state).
        # We re-init git so the derivative looks like a fresh checkout.
        cp -R "$local_clone" "$target"
        rm -rf "$target/.git"
        (
            cd "$target"
            git -c init.defaultBranch=main init --quiet
            git config user.email "smoke-test@example.test"
            git config user.name "Smoke Test"
            git add -A
            git commit -q -m "imported from local template clone for smoke test"
        )
        return 0
    fi

    # Network-clone mode
    if git clone --quiet "$repo" "$target" 2>/dev/null; then
        # Reset git config so commits made during the smoke test have a
        # known author.
        (
            cd "$target"
            git config user.email "smoke-test@example.test"
            git config user.name "Smoke Test"
        )
        return 0
    fi

    return 1
}

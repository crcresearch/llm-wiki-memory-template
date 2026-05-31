#!/usr/bin/env bash
# Sandbox helpers for the multi-agent write protocol prototype.
#
# Creates a temporary directory containing:
#   - origin.git/    : a bare git repo standing in for the shared remote
#   - main/          : the "canonical" working clone (initial wiki content)
#   - agent-<handle>/ : per-agent local clones
#
# Sandboxes are torn down by SANDBOX_CLEANUP unless KEEP_SANDBOX=1.

setup_sandbox() {
    SANDBOX="$(mktemp -d -t multi-agent-proto-XXXX)"
    # macOS mktemp returns /var/folders/... which is a symlink to
    # /private/var/folders/...; canonicalize so git's working-tree paths
    # match what callers see.
    SANDBOX="$(cd "$SANDBOX" && pwd -P)"
    export SANDBOX

    # Bare origin (the shared remote).
    git init --bare --quiet "$SANDBOX/origin.git"

    # Initial canonical clone: scaffold the wiki structure, commit, push.
    git clone --quiet "$SANDBOX/origin.git" "$SANDBOX/main"
    git -C "$SANDBOX/main" config user.email "init@sandbox"
    git -C "$SANDBOX/main" config user.name "Sandbox Init"

    mkdir -p "$SANDBOX/main"
    cat > "$SANDBOX/main/index_proto.md" <<'EOF'
# Index

- [Welcome](Welcome): the seed page
EOF
    cat > "$SANDBOX/main/log_proto.md" <<'EOF'
# Log
EOF
    cat > "$SANDBOX/main/Welcome.md" <<'EOF'
# Welcome

The seed page for the protocol prototype sandbox.
EOF

    git -C "$SANDBOX/main" add index_proto.md log_proto.md Welcome.md
    git -C "$SANDBOX/main" commit -m "Initial sandbox wiki" --quiet
    git -C "$SANDBOX/main" branch -M main
    git -C "$SANDBOX/main" push -u origin main --quiet
}

# Create a per-agent clone. Args: handle.
clone_for_agent() {
    local handle="$1"
    local dir="$SANDBOX/agent-$handle"
    git clone --quiet "$SANDBOX/origin.git" "$dir"
    git -C "$dir" config user.email "$handle@sandbox"
    git -C "$dir" config user.name "agent-$handle"
    echo "$dir"
}

cleanup_sandbox() {
    if [ -n "${KEEP_SANDBOX:-}" ]; then
        echo "  sandbox kept at $SANDBOX"
        return
    fi
    if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    rm -f /tmp/.protocol_branch_seq.$$
}

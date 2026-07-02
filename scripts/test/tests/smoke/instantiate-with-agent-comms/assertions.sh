#!/usr/bin/env bash
# Assertions for the instantiate.sh --features=agent-comms smoke test.
#
# Verifies the integration path: a fresh template + --features=agent-comms
# produces a derived project that has both the base bootstrap AND the
# agent-comms feature installed in one shot, equivalent to instantiating
# without --features= and then running enable-feature.sh agent-comms.

T="$SANDBOX/template-comms"

if [ ! -d "$T" ]; then
    skip "instantiate-with-agent-comms assertions" \
         "template not cloned (offline + no MVP_TEMPLATE_LOCAL, or MVP_TEMPLATE_LOCAL is derived)"
    return 0 2>/dev/null || true
fi

# Exit status first: the assertions below are presence-conditional and can
# pass against a half-bootstrapped tree (mid-run deaths were WARN-swallowed).
assert "instantiate.sh --features=agent-comms exited 0" \
    "[ \"\$(cat '$T.instantiate-rc' 2>/dev/null)\" = '0' ]"

REPO_NAME=$(basename "$T")  # template-comms

# --- Base bootstrap happened ---
assert "instantiate.sh produced CLAUDE.md" \
    "[ -f '$T/CLAUDE.md' ]"
assert_contains "CLAUDE.md has project name substituted" \
    "$T/CLAUDE.md" "Agent Comms Smoke Test"
assert "CLAUDE.md has no {{PROJECT_NAME}} leak" \
    "! grep -q '{{PROJECT_NAME}}' '$T/CLAUDE.md'"
assert "wiki sub-repo created (init-wiki.sh ran)" \
    "[ -d '$T/wiki/${REPO_NAME}.wiki/.git' ]"
assert "Home_${REPO_NAME}.md exists in the wiki sub-repo" \
    "[ -f '$T/wiki/${REPO_NAME}.wiki/Home_${REPO_NAME}.md' ]"

# --- --agent=none honored: no overlay dirs ---
assert "no .claude/ overlay copied (--agent=none)" \
    "[ ! -d '$T/.claude' ]"
assert "no .cursor/ overlay copied (--agent=none)" \
    "[ ! -d '$T/.cursor' ]"

# --- Feature install ran as part of instantiate.sh ---
assert "scripts/agent-comms/ created via --features=" \
    "[ -d '$T/scripts/agent-comms' ]"
assert "scripts/agent-comms/ask.sh installed" \
    "[ -f '$T/scripts/agent-comms/ask.sh' ]"
assert "scripts/agent-comms/enroll.sh installed" \
    "[ -f '$T/scripts/agent-comms/enroll.sh' ]"
assert "scripts/agent-comms/README.md installed" \
    "[ -f '$T/scripts/agent-comms/README.md' ]"

# --- .features-enabled recorded by install_feature ---
assert ".features-enabled created" \
    "[ -f '$T/.features-enabled' ]"
assert ".features-enabled lists agent-comms" \
    "grep -qFx 'agent-comms' '$T/.features-enabled'"

# --- CLAUDE.md patched with our section (between paired markers) ---
assert "CLAUDE.md has opening marker for agent-comms" \
    "grep -qF '<!-- feature:agent-comms -->' '$T/CLAUDE.md'"
assert "CLAUDE.md has closing marker for agent-comms" \
    "grep -qF '<!-- /feature:agent-comms -->' '$T/CLAUDE.md'"
assert "CLAUDE.md mentions 'Cross-agent communication'" \
    "grep -qF 'Cross-agent communication' '$T/CLAUDE.md'"
assert "CLAUDE.md mentions enroll.sh next-step" \
    "grep -qF 'scripts/agent-comms/enroll.sh' '$T/CLAUDE.md'"

# --- CI workflow installed ---
assert ".github/workflows/agent-comms.yml created" \
    "[ -f '$T/.github/workflows/agent-comms.yml' ]"

# --- Scripts retain their executability after the cp-based install ---
assert "installed ask.sh is executable" \
    "[ -x '$T/scripts/agent-comms/ask.sh' ]"
assert "installed enroll.sh is executable" \
    "[ -x '$T/scripts/agent-comms/enroll.sh' ]"

#!/usr/bin/env bash
# Real-repo verification on macOS bash 3.2.57 for the 2 new fixtures
# added to PR #59 in the review-resolution round:
#   GW-D: --apply --github-wiki --agent=none against FHI360_Lite scratch
#   GW-E: dry-run --github-wiki against FHI360_Lite scratch (no --apply)

set -uo pipefail

bash --version | head -1
echo ""

cd ~/llm-wiki-memory-template
git fetch origin
git checkout feature/adopt-github-wiki && git pull --ff-only
echo "HEAD: $(git rev-parse --short HEAD)"
echo ""

SCRATCH_ROOT=$(mktemp -d -t fhi360-gw-new)
echo "Scratch root: $SCRATCH_ROOT"
echo ""

echo "================================================================"
echo "Test GW-D: FHI360_Lite + --apply --github-wiki --agent=none"
echo "================================================================"

D_DIR="$SCRATCH_ROOT/testGWD"
git clone --quiet --depth=1 https://github.com/chrissweet/FHI360_Lite.git "$D_DIR"
cd "$D_DIR"
git remote set-url origin "https://github.com/example-org-fake/fhi360-gw-agent-none.git"
git -c user.email=t@x -c user.name=t add -A 2>/dev/null
git -c user.email=t@x -c user.name=t commit -q -m stage 2>/dev/null

echo "--- --apply --github-wiki --agent=none ---"
bash ~/llm-wiki-memory-template/scripts/adopt.sh --target=. --apply --github-wiki --agent=none 2>&1 | tail -10
RC=$?
echo "RC=$RC"

echo ""
echo "--- Manifest sub-step lines ---"
grep -E "^- (init|github|overlay)" .llm-wiki-adopt-log.md

echo ""
echo "--- TOUCH applied ---"
awk '/^- TOUCH applied/,/^$/' .llm-wiki-adopt-log.md

echo ""
echo "--- Agent-none gating verification ---"
echo "CLAUDE.md has NO lw:memory-boundary sentinel: $(grep -c 'lw:memory-boundary' CLAUDE.md 2>/dev/null | awk '{print ($1==0 ? "YES" : "NO")}')"
echo ".claude/settings.json NOT created (overlay skipped): $([[ ! -f .claude/settings.json ]] && echo YES || echo NO)"
echo ".gitignore got the wiki rule (append-only TOUCH ran without overlay): $(grep -c 'wiki/\*.wiki/' .gitignore 2>/dev/null)"
echo "init-wiki: NO --github flag (seed-push 404, local fallback): $(grep -c 'init-wiki:.*--github' .llm-wiki-adopt-log.md | awk '{print ($1==0 ? "YES" : "NO")}')"
echo ""

echo "================================================================"
echo "Test GW-E: FHI360_Lite + dry-run --github-wiki (no --apply)"
echo "================================================================"

E_DIR="$SCRATCH_ROOT/testGWE"
git clone --quiet --depth=1 https://github.com/chrissweet/FHI360_Lite.git "$E_DIR"
cd "$E_DIR"
git remote set-url origin "https://github.com/example-org-fake/fhi360-gw-dryrun-preview.git"

echo "--- dry-run --github-wiki (NO --apply) ---"
bash ~/llm-wiki-memory-template/scripts/adopt.sh --target=. --github-wiki 2>&1 | awk '/^GITHUB WIKI/,/^$/'

echo ""
echo "--- Dry-run did NOT mutate the host ---"
echo "manifest NOT written: $([ ! -f .llm-wiki-adopt-log.md ] && echo YES || echo NO)"
echo "llm-wiki.md NOT copied: $([ ! -f llm-wiki.md ] && echo YES || echo NO)"
echo "wiki sub-repo NOT created: $([ ! -d wiki ] && echo YES || echo NO)"
echo ".claude/ NOT created: $([ ! -d .claude ] && echo YES || echo NO)"
echo "host .gitignore unchanged (no wiki rule): $(grep -c 'wiki/\*.wiki/' .gitignore 2>/dev/null | awk '{print ($1==0 ? "YES" : "NO")}')"
echo ""

echo "================================================================"
echo "ALL DONE."
echo "  rm -rf $SCRATCH_ROOT when done."
echo "================================================================"

#!/usr/bin/env python3
"""SessionStart hook: ensure the project's durable-memory wiki is present.

This project keeps its durable memory in a separate wiki repository that
lives at wiki/<repo-name>.wiki/. That repository is NOT committed inside
the main repo, so a fresh checkout will not have it. When it is missing,
this hook clones it directly using the SAME VCS that manages this repo,
detected from the metadata directory at the repo root (.jj before .git,
since jj colocates with git). A jj checkout gets `jj git clone`; a plain
git checkout gets `git clone`.

The clone runs non-interactively with a timeout, so it can never hang or
block on a credential prompt at session start. If it succeeds, the hook is
silent (the separate wiki-surfacing hook takes over). If it fails (no
network, private repo needing auth, wiki not created yet), the hook falls
back to emitting additionalContext asking the agent to clone it, including
the exact command for this repo's VCS.

The wiki location is derived from the main repo's "origin" remote, so the
hook needs no per-project substitution.

Output contract: at most one JSON object on stdout using the SessionStart
hookSpecificOutput.additionalContext channel. Any unexpected condition
(not a repo, no origin) is treated as "nothing to do" and exits cleanly.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional

# How long the clone may take before we give up and fall back to nudging.
CLONE_TIMEOUT_SECONDS = 30


def git(*args: str) -> Optional[str]:
    """Run a git command, returning stripped stdout or None on any failure."""
    try:
        out = subprocess.run(
            ["git", *args],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return out.stdout.strip() or None


def detect_clone_command(repo_root: Path, url: str, dest: str) -> Optional[List[str]]:
    """Pick the clone command for the VCS that manages repo_root.

    Order matters: jj colocates with git, so both .jj and .git exist in a jj
    checkout and .jj must win. Returns None if no known VCS marker is found.

    The jj clone passes --colocate so the wiki gets a working .git alongside
    .jj, keeping the wiki git-operable (the surfacing hook's `git -C wiki
    commit` guidance drives it through git) regardless of the jj version's
    clone default.
    """
    if (repo_root / ".jj").is_dir():
        return ["jj", "git", "clone", "--colocate", url, dest]
    if (repo_root / ".sl").is_dir():
        return ["sl", "clone", url, dest]
    if (repo_root / ".hg").is_dir():
        return ["hg", "clone", f"git+{url}", dest]
    if (repo_root / ".git").exists():  # file (worktree) or dir
        return ["git", "clone", url, dest]
    return None


def try_clone(cmd: List[str], repo_root: Path, wiki_rel: str) -> bool:
    """Clone into a unique staging dir, then atomically rename into place.

    Cloning straight to the canonical path has two failure modes. A clone
    killed by the timeout (SIGKILL, so the tool never runs its own cleanup)
    leaves a half-written directory that later sessions mistake for a finished
    checkout. And two sessions starting together race on the same destination.
    Both are avoided by staging each clone in its own directory and publishing
    it with a single os.rename: an interrupted clone only ever strands the
    staging dir, so the canonical path stays absent and the next session
    retries; concurrent sessions each stage independently, then the first
    rename wins and the rest find the path already populated.

    The staging dir is a sibling of the canonical path (same filesystem, so
    the rename is atomic) and is named "*.wiki" so the repo's `wiki/*.wiki/`
    ignore covers it during the clone window. The clone targets a child of the
    staging dir so the VCS creates its own destination rather than cloning into
    the pre-existing (and for some tools non-empty) staging dir itself.
    """
    final_dest = repo_root / wiki_rel
    parent = final_dest.parent
    parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".ensure-wiki-", suffix=".wiki", dir=parent))
    clone_target = staging / "repo"
    # detect_clone_command always puts the destination last; swap it for the
    # staging target while leaving the user-facing command (for the nudge)
    # pointed at the canonical path.
    staged_cmd = [*cmd[:-1], str(clone_target)]
    env = {
        **os.environ,
        # Never block on a terminal/SSH credential prompt at session start.
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_SSH_COMMAND": "ssh -oBatchMode=yes",
    }
    try:
        try:
            subprocess.run(
                staged_cmd,
                cwd=repo_root,
                env=env,
                capture_output=True,
                check=True,
                timeout=CLONE_TIMEOUT_SECONDS,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
            return False
        try:
            os.rename(clone_target, final_dest)
        except OSError:
            # A concurrent session published the canonical path first; renaming
            # onto its non-empty directory fails. Treat its checkout as ours.
            return final_dest.is_dir()
        return True
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def github_wiki_url(origin: str) -> Optional[str]:
    """Derive the GitHub project-wiki URL from an origin remote URL.

    Mirrors the shared bash helper lw_wiki_url (scripts/lib/git.sh): a GitHub
    project wiki lives at the same URL with a ".wiki.git" suffix, and that
    convention is GitHub-only. Returns None for any non-GitHub host. The bash
    side fails loud there (it backs an explicit --github request); this hook
    runs automatically every session, so a non-GitHub origin is simply
    "nothing to do" rather than an error.
    """
    rest = origin
    if "://" in rest:  # scheme://[user@]host/...
        rest = rest.split("://", 1)[1].split("@", 1)[-1]
    elif "@" in rest and ":" in rest:  # scp-style user@host:path
        rest = rest.split("@", 1)[1]
    host = re.split(r"[:/]", rest, maxsplit=1)[0]
    if "github" not in host:
        return None
    base = origin[:-4] if origin.endswith(".git") else origin
    return f"{base}.wiki.git"


def repo_name_from_origin(origin: str) -> Optional[str]:
    """Repo name (last path component) from an origin URL.

    Mirrors the shared bash helpers lw_repo_slug / lw_repo_from_url
    (scripts/lib/git.sh) so the wiki directory this hook targets matches the
    one init-wiki.sh creates and the one baked into the surfacing hook as
    ${REPO_NAME} (both via lw_name_from_origin). Deriving from origin rather
    than the local checkout directory name is what keeps a renamed or forked
    clone pointing at the same wiki/<name>.wiki/ as the rest of the tooling.
    Returns None if no name can be parsed.
    """
    s = origin[:-4] if origin.endswith(".git") else origin
    s = s.rstrip("/")
    if "://" in s:  # scheme://[user@]host/owner/repo -> drop scheme, host
        s = s.split("://", 1)[1].split("/", 1)[-1]
    elif "@" in s and ":" in s:  # scp-style user@host:owner/repo -> drop host
        s = s.split(":", 1)[1]
    name = s.rsplit("/", 1)[-1]
    return name or None


def emit(message: str) -> None:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": message,
            }
        },
        sys.stdout,
    )


def main() -> int:
    # Resolve the repo root; bail quietly if we are not in a working tree.
    root = git("rev-parse", "--show-toplevel")
    if not root:
        return 0
    repo_root = Path(root)

    # Identity and clone source both come from origin. Without it there is no
    # wiki to clone and no canonical name to look under, so exit quietly.
    origin = git("-C", root, "remote", "get-url", "origin")
    if not origin:
        return 0

    # Name the wiki from origin (mirrors lw_name_from_origin / init-wiki.sh and
    # the ${REPO_NAME} baked into the surfacing hook), falling back to the
    # checkout directory name only if origin cannot be parsed. Using the local
    # directory name here would diverge from the rest of the tooling on a
    # renamed or forked clone.
    repo_name = repo_name_from_origin(origin) or repo_root.name

    # The wiki lives alongside the repo, as its own checkout.
    wiki_rel = f"wiki/{repo_name}.wiki"
    if (repo_root / wiki_rel).is_dir():
        # Already present: nothing to do. The canonical path is only ever
        # created by the atomic rename in try_clone, so its existence means a
        # complete checkout, never a half-written clone.
        return 0

    # The wiki URL is GitHub-only (see github_wiki_url); a non-GitHub host means
    # there is no wiki to auto-clone, so exit quietly.
    wiki_url = github_wiki_url(origin)
    if not wiki_url:
        return 0

    cmd = detect_clone_command(repo_root, wiki_url, wiki_rel)
    if cmd and try_clone(cmd, repo_root, wiki_rel):
        # Cloned successfully; stay silent and let the wiki-surfacing hook run.
        return 0

    # Clone unavailable or failed: ask the agent to do it, naming the exact
    # command for this repo's VCS (falling back to plain wording if unknown).
    how = f"with `{' '.join(cmd)}`" if cmd else f"from {wiki_url}"
    emit(
        f"The project's durable-memory wiki could not be auto-cloned to "
        f"{wiki_rel}/. Clone it {how} before reading or writing wiki memory."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

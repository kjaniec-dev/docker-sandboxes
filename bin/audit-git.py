#!/usr/bin/env python3
"""Detect command-bearing repository Git metadata without executing repository Git."""
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import time


class UnsafeMetadata(Exception):
    pass


def regular(path, directory=False):
    mode = path.lstat().st_mode
    if not (stat.S_ISDIR(mode) if directory else stat.S_ISREG(mode)):
        raise UnsafeMetadata(f"{path}: expected a real {'directory' if directory else 'file'}")


# "transport::address" URLs make Git run git-remote-<transport>; ext:: runs a shell command.
REMOTE_HELPER = re.compile(r"^[a-z0-9+.-]+::", re.IGNORECASE)


def command_key(key, value):
    key = key.lower()
    if key.startswith("url.") and REMOTE_HELPER.match(key[4:]):
        return True
    if key.endswith((".url", ".pushurl", ".insteadof", ".pushinsteadof")) and REMOTE_HELPER.match(value):
        return True
    if key.startswith("submodule.") and key.endswith(".update"):
        return value.startswith("!")
    if key.startswith("alias."):
        try:
            words = shlex.split(value)
        except ValueError:
            return True
        # Non-shell aliases may still inject global -c/--config-env settings.
        return bool(words and words[0].startswith(("!", "-")))
    return (
        key in {
            "core.fsmonitor", "core.hookspath", "core.sshcommand", "core.pager",
            "core.editor", "core.gitproxy", "core.askpass", "sequence.editor",
            "diff.external", "gpg.program", "ssh.variant", "core.alternaterefscommand",
            "gc.recentobjectshook", "interactive.difffilter",
            "gpg.ssh.defaultkeycommand",
        }
        or key.startswith(("filter.", "pager."))
        or (key.startswith("credential.") and key.endswith(".helper"))
        or (key.startswith("diff.") and key.endswith((".textconv", ".command")))
        or (key.startswith("merge.") and key.endswith(".driver"))
        or (key.startswith(("difftool.", "mergetool.")) and key.endswith((".cmd", ".command", ".path")))
        or (key.startswith(("trailer.", "tar.")) and key.endswith((".cmd", ".command")))
        or (key.startswith("hook.") and key.endswith(".command"))
        or key == "protocol.allow"
        or (key.startswith("protocol.") and key.endswith(".allow"))
        or (key.startswith("sendemail.") and key.endswith("cmd"))
        or (key.startswith(("browser.", "man.")) and key.endswith(".cmd"))
        or (key.startswith("remote.") and key.endswith(".vcs"))
        or (key.startswith("gpg.") and key.endswith(".program"))
        or (key.startswith("remote.") and key.endswith((".uploadpack", ".receivepack", ".proxy")))
        or key.startswith(("include.", "includeif."))
    )


def audit_config(path, root):
    regular(path)
    # --file ignores other config scopes; --no-includes makes dormant includeIf
    # entries visible without opening untrusted paths. Reject includes below.
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    result = subprocess.run(
        ["git", "--no-pager", "config", "--null", "--no-includes", "--file", str(path), "--list"],
        cwd="/", env=env, capture_output=True,
    )
    if result.returncode:
        raise UnsafeMetadata(f"{path}: cannot parse Git configuration")
    for entry in result.stdout.split(b"\0"):
        if not entry:
            continue
        key, _, value = entry.partition(b"\n")
        key = os.fsdecode(key)
        value = os.fsdecode(value)
        if command_key(key, value):
            # Never print values: they can contain credentials or terminal escapes.
            raise UnsafeMetadata(f"{path}: prohibited setting {ascii(key)}")
        if key.lower() == "core.worktree":
            target = Path(value)
            target = target if target.is_absolute() else path.parent / target
            if not target.resolve().is_relative_to(root):
                raise UnsafeMetadata(f"{path}: core.worktree escapes the workspace")


def audit_worktrees(root):
    """Allow only genuine linked worktrees under .worktrees/.

    Host Git reads the config of any repository the user enters, so a nested
    clone, a bare repository or a worktree redirected elsewhere would execute
    commands on `cd .worktrees/x && git status`.
    """
    base = root / ".worktrees"
    if not os.path.lexists(base):
        return
    regular(base, directory=True)
    registry = (root / ".git" / "worktrees").resolve()
    pending = [base]
    while pending:
        directory = pending.pop()
        for path in directory.iterdir():
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                raise UnsafeMetadata(f"{path}: symlink in .worktrees")
            if path.name == ".git":
                raise UnsafeMetadata(f"{path}: .git directly under a non-worktree directory")
            if not stat.S_ISDIR(mode):
                continue
            marker = path / ".git"
            if os.path.lexists(marker):
                regular(marker)
                text = marker.read_text()
                if not text.startswith("gitdir: ") or "\n" in text.strip():
                    raise UnsafeMetadata(f"{marker}: malformed worktree link")
                target = Path(text[len("gitdir: "):].strip())
                target = target if target.is_absolute() else path / target
                regular(target, directory=True)
                if target.parent.resolve() != registry:
                    raise UnsafeMetadata(f"{marker}: worktree link does not point into the repository's worktree registry")
            elif all(os.path.lexists(path / name) for name in ("HEAD", "objects", "refs")):
                raise UnsafeMetadata(f"{path}: bare repository in .worktrees")
            else:
                pending.append(path)


def audit(root, expected_identity=None):
    metadata = root / ".git"
    regular(metadata, directory=True)
    info = metadata.stat()
    identity = f"{info.st_dev}:{info.st_ino}"
    if expected_identity is not None and expected_identity != identity:
        raise UnsafeMetadata(f"{metadata}: Git metadata directory was replaced during the session")
    if not (metadata / "config").exists():
        raise UnsafeMetadata(f"{metadata}: missing Git configuration")
    # Git's main checkout, linked worktrees and submodules have metadata here.
    # Skip object/ref stores; audit administrative directories without following links.
    pending = [metadata]
    visited = set()
    while pending:
        directory = pending.pop()
        regular(directory, directory=True)
        directory_identity = directory.resolve()
        if directory_identity in visited:
            continue
        visited.add(directory_identity)
        metadata_root = directory == metadata or ((directory / "config").is_file() and (directory / "HEAD").is_file())
        for path in directory.iterdir():
            if metadata_root and path.name in {"objects", "refs", "logs", "lfs"}:
                continue
            if path.name in {"config", "config.worktree"}:
                audit_config(path, root)
            elif path.name == "hooks":
                regular(path, directory=True)
                for hook in path.iterdir():
                    regular(hook)
                    if not hook.name.endswith(".sample"):
                        raise UnsafeMetadata(f"{hook}: non-sample Git hook")
            elif path.name in {"commondir", "gitdir"}:
                regular(path)
                target = Path(path.read_text().strip())
                target = target if target.is_absolute() else path.parent / target
                boundary = metadata if path.name == "commondir" else root
                if (path.name == "commondir" and path.parent == metadata) or not target.resolve().is_relative_to(boundary):
                    raise UnsafeMetadata(f"{path}: Git metadata routing escapes the workspace")
                if path.name == "commondir":
                    pending.append(target.resolve())
            elif path.is_symlink():
                raise UnsafeMetadata(f"{path}: metadata symlink")
            elif path.is_dir():
                pending.append(path)
    audit_worktrees(root)
    return identity


def quarantine(root):
    """Hide unsafe metadata from host Git and prompts without deleting anything."""
    target = root / f".git.sbx-quarantine-{time.strftime('%Y%m%dT%H%M%S', time.gmtime())}-{os.getpid()}"
    os.rename(root / ".git", target)
    return target


def discover():
    for path in (Path.cwd(), *Path.cwd().parents):
        if any(path.glob(".git.sbx-quarantine-*")):
            raise UnsafeMetadata(f"{path}: quarantined Git metadata present; inspect it and restore or remove it")
        if (path / ".git").exists() or (path / ".git").is_symlink():
            if not (path / ".git").is_dir():
                raise UnsafeMetadata("linked worktree: launch from the main Git checkout")
            return path
    raise UnsafeMetadata("run from inside a Git repository")


def main():
    try:
        if len(sys.argv) not in {2, 3}:
            raise UnsafeMetadata("usage: audit-git.py <--discover|--identity root|root [identity]>")
        if any(os.environ.get(key) for key in ("GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")):
            raise UnsafeMetadata("unset Git repository-routing environment variables before launching")
        if sys.argv[1] == "--quarantine" and len(sys.argv) == 3:
            print(quarantine(Path(sys.argv[2])))
            return 0
        if sys.argv[1] == "--identity":
            if len(sys.argv) != 3:
                raise UnsafeMetadata("--identity requires a repository root")
            print(audit(Path(sys.argv[2])))
            return 0
        root = discover() if sys.argv[1] == "--discover" else Path(sys.argv[1])
        audit(root, sys.argv[2] if len(sys.argv) == 3 else None)
        if sys.argv[1] == "--discover":
            print(root)
    except (UnsafeMetadata, OSError, ValueError) as error:
        print(f"sbx-dev: Git metadata audit failed: {error}", file=sys.stderr)
        print("Inspect and repair metadata with trusted tools before running host Git or a Git-aware shell prompt; see docs/git-metadata.md.", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())

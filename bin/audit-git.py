#!/usr/bin/env python3
"""Detect command-bearing repository Git metadata without executing repository Git."""
import json
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
QUARANTINE_RECOVERY = (
    "quarantined Git metadata present; do not run Git or use a Git-aware prompt inside it "
    "before manually inspecting config and hooks with trusted tools; then restore or remove it"
)


def command_key(key, value):
    # Git folds section and variable names, but preserves subsection case.
    section, _, rest = key.partition(".")
    subsection, separator, variable = rest.rpartition(".")
    section = section.lower()
    variable = (variable if separator else rest).lower()
    if section == "sendemail" and variable == "smtpserver":
        # git-send-email treats absolute paths as sendmail executables.
        return value.startswith("/")
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
            "init.templatedir",
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
        or (section in {"man", "browser"} and variable in {"cmd", "path"})
        or (key.startswith("gpg.") and key.endswith(".program"))
        or (key.startswith("remote.") and key.endswith((".uploadpack", ".receivepack", ".proxy", ".vcs")))
        or key.startswith(("include.", "includeif."))
    )


def audit_config(path, root, allow_integrations=False):
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
        if command_key(key, value) and (
            not allow_integrations or key.lower().startswith(("include.", "includeif."))
        ):
            # Never print values: they can contain credentials or terminal escapes.
            # Rewrite bases live in keys and can contain commands/credentials too.
            if key.lower().startswith("url."):
                key = "url.<base>." + key.rsplit(".", 1)[-1]
            raise UnsafeMetadata(f"{path}: prohibited setting {ascii(key)}")
        if key.lower() == "core.worktree":
            target = Path(value)
            target = target if target.is_absolute() else path.parent / target
            if not target.resolve().is_relative_to(root):
                raise UnsafeMetadata(f"{path}: core.worktree escapes the workspace")


def audit_worktrees(root, allow_integrations=False):
    """Audit linked worktrees and independent repositories under .worktrees/.

    Host Git reads the config of any repository the user enters, so a nested
    clone, a bare repository or a worktree redirected elsewhere would execute
    commands on `cd .worktrees/x && git status`.
    """
    base = root / ".worktrees"
    if not os.path.lexists(base):
        return
    regular(base, directory=True)
    pending = [(base, root, False)]
    while pending:
        directory, owner, inside_repository = pending.pop()
        for path in directory.iterdir():
            mode = path.lstat().st_mode
            if path.name.startswith(".git.sbx-quarantine-"):
                raise UnsafeMetadata(f"{path}: {QUARANTINE_RECOVERY}")
            if stat.S_ISLNK(mode):
                if inside_repository:
                    # Source symlinks are ordinary checkout content; never follow them.
                    continue
                raise UnsafeMetadata(f"{path}: symlink in .worktrees")
            if path.name == ".git":
                if inside_repository:
                    # This repository's metadata was audited before entering its sources.
                    continue
                raise UnsafeMetadata(f"{path}: .git directly under a non-worktree directory")
            if not stat.S_ISDIR(mode):
                continue
            marker = path / ".git"
            if os.path.lexists(marker):
                if stat.S_ISDIR(marker.lstat().st_mode):
                    audit(path, scan_worktrees=False, allow_integrations=allow_integrations)
                    pending.append((path, path, True))
                    continue
                regular(marker)
                text = marker.read_text()
                if not text.startswith("gitdir: ") or "\n" in text.strip():
                    raise UnsafeMetadata(f"{marker}: malformed worktree link")
                target = Path(text[len("gitdir: "):].strip())
                target = target if target.is_absolute() else path / target
                regular(target, directory=True)
                if target.parent.resolve() != (owner / ".git" / "worktrees").resolve():
                    raise UnsafeMetadata(f"{marker}: worktree link does not point into the repository's worktree registry")
                pending.append((path, owner, True))
            elif all(os.path.lexists(path / name) for name in ("HEAD", "objects", "refs")):
                raise UnsafeMetadata(f"{path}: bare repository in .worktrees")
            else:
                pending.append((path, owner, inside_repository))


def audit_hooks(directory):
    regular(directory, directory=True)
    pending = [directory]
    while pending:
        current = pending.pop()
        for hook in current.iterdir():
            if hook.is_symlink():
                raise UnsafeMetadata(f"{hook}: metadata symlink")
            if hook.is_dir():
                # Git executes files directly under hooks, not saved subdirectories.
                # Still inspect those directories for metadata symlinks.
                pending.append(hook)
            else:
                regular(hook)
                if current == directory and not hook.name.endswith(".sample"):
                    raise UnsafeMetadata(f"{hook}: non-sample Git hook")


def audit(root, expected_identity=None, scan_worktrees=True, allow_integrations=False):
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
                audit_config(path, root, allow_integrations=allow_integrations)
            elif path.name == "hooks":
                if not allow_integrations:
                    audit_hooks(path)
            elif path.name in {"commondir", "gitdir"}:
                regular(path)
                if path.name == "gitdir" and path.parent.parent.name == "worktrees":
                    # worktrees/<id>/gitdir points BACK to a linked checkout's
                    # .git file, which may be external or temporarily unavailable.
                    # Never read or traverse that external backpointer target.
                    continue
                routing = path.read_text().strip()
                if path.name == "commondir" and not routing:
                    raise UnsafeMetadata(f"{path}: stale commondir target (empty routing file)")
                target = Path(routing)
                target = target if target.is_absolute() else path.parent / target
                if path.name == "commondir" and not target.is_dir():
                    raise UnsafeMetadata(f"{path}: stale commondir target (missing or not a directory)")
                boundary = metadata if path.name == "commondir" else root
                if (path.name == "commondir" and path.parent == metadata) or not target.resolve().is_relative_to(boundary):
                    raise UnsafeMetadata(f"{path}: Git metadata routing escapes the workspace")
                if path.name == "commondir":
                    pending.append(target.resolve())
            elif path.is_symlink():
                raise UnsafeMetadata(f"{path}: metadata symlink")
            elif path.is_dir():
                pending.append(path)
    if scan_worktrees:
        audit_worktrees(root, allow_integrations=allow_integrations)
    return identity


def quarantine(root):
    """Hide unsafe metadata from host Git and prompts without deleting anything."""
    suffix = f".git.sbx-quarantine-{time.strftime('%Y%m%dT%H%M%S', time.gmtime())}-{os.getpid()}"
    errors = []
    moved = set()
    pending = [root]
    while pending:
        directory = pending.pop()
        metadata = directory / ".git"
        if os.path.lexists(metadata):
            target = directory / suffix
            try:
                os.rename(metadata, target)
            except OSError as error:
                errors.append(str(error))
            else:
                moved.add(target)
                yield target
        try:
            # Protect the main repository first, even if descendant discovery fails.
            children = [root / ".worktrees"] if directory == root else directory.iterdir()
            for path in children:
                if path.name == ".git" or path in moved:
                    continue
                if not path.is_symlink() and path.is_dir():
                    pending.append(path)
        except OSError as error:
            errors.append(str(error))
    if errors:
        raise UnsafeMetadata("Git metadata quarantine incomplete: " + "; ".join(errors))


def discover():
    for path in (Path.cwd(), *Path.cwd().parents):
        if any(path.glob(".git.sbx-quarantine-*")):
            raise UnsafeMetadata(f"{path}: {QUARANTINE_RECOVERY}")
        if (path / ".git").exists() or (path / ".git").is_symlink():
            if not (path / ".git").is_dir():
                raise UnsafeMetadata("linked worktree: launch from the main Git checkout")
            return path
    raise UnsafeMetadata("run from inside a Git repository")


def main():
    try:
        args = sys.argv[1:]
        allow_integrations = args[:1] == ["--allow-integrations"]
        if args[:1] in (["--allow-integrations"], ["--strict"]):
            args = args[1:]
        if len(args) not in {1, 2}:
            raise UnsafeMetadata("usage: audit-git.py [--allow-integrations|--strict] <--discover|--discover-identity|--identity root|--quarantine root|root [identity]>")
        if any(os.environ.get(key) for key in ("GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")):
            raise UnsafeMetadata("unset Git repository-routing environment variables before launching")
        if args[0] == "--quarantine" and len(args) == 2:
            for target in quarantine(Path(args[1])):
                print(target, flush=True)
            return 0
        if args[0] == "--identity":
            if len(args) != 2:
                raise UnsafeMetadata("--identity requires a repository root")
            print(audit(Path(args[1]), allow_integrations=allow_integrations))
            return 0
        discovering = args[0] in {"--discover", "--discover-identity"}
        if discovering and len(args) != 1:
            raise UnsafeMetadata(f"{args[0]} does not accept arguments")
        root = discover() if discovering else Path(args[0])
        identity = audit(root, args[1] if len(args) == 2 else None,
                         allow_integrations=allow_integrations)
        if args[0] == "--discover-identity":
            print(json.dumps([str(root), identity]))
        elif args[0] == "--discover":
            print(root)
    except (UnsafeMetadata, OSError, ValueError) as error:
        print(f"sbx-dev: Git metadata audit failed: {error}", file=sys.stderr)
        print("Inspect and repair metadata with trusted tools before running host Git or a Git-aware shell prompt; see docs/git-metadata.md.", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())

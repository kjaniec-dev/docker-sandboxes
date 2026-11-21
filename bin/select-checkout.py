#!/usr/bin/env python3
"""Select a registered local worktree of the launcher's own repository."""
import os
from pathlib import Path
import sys


def owner(checkout):
    marker = checkout / '.git'
    if marker.is_symlink():
        return None
    if marker.is_dir():
        return checkout
    if not marker.is_file():
        return None
    try:
        text = marker.read_text()
        if not text.startswith('gitdir: ') or '\n' in text.strip():
            return None
        admin = Path(text[len('gitdir: '):].strip())
        if not admin.is_absolute():
            admin = checkout / admin
        if admin.is_symlink() or not admin.is_dir():
            return None
        admin = admin.resolve()
        if admin.parent.name != 'worktrees' or admin.parent.parent.name != '.git':
            return None
        root = admin.parent.parent.parent
        if (root / '.git').is_symlink() or not (root / '.git').is_dir():
            return None
        if (root / '.worktrees').is_symlink() or not checkout.is_relative_to((root / '.worktrees').resolve()):
            return None
        backlink = admin / 'gitdir'
        if backlink.is_symlink() or not backlink.is_file():
            return None
        link = Path(backlink.read_text().strip())
        if not link.is_absolute():
            link = admin / link
        return root if link.resolve() == marker.resolve() else None
    except (OSError, ValueError):
        return None


def select(installed, cwd):
    installed, cwd = installed.resolve(), cwd.resolve()
    common = owner(installed)
    if common is None:
        return installed
    for directory in (cwd, *cwd.parents):
        if os.path.lexists(directory / '.git'):
            return directory if owner(directory) == common else installed
    return installed


if __name__ == '__main__':
    selected = select(Path(sys.argv[1]), Path.cwd())
    if '\n' in str(selected):
        sys.exit('sbx-dev: checkout paths containing newlines are not supported')
    print(selected)

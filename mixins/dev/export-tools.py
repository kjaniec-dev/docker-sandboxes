#!/usr/bin/env python3
"""Export tool dependency closures without overlaying a workload's OS or libc."""
from pathlib import Path
import re
import shutil
import subprocess


def write_wrapper(root, name, target):
    wrapper = root / "bin" / name
    guard = ""
    if name == "jq":
        guard = ('if [ "$#" -eq 4 ] && [ "$1" = "-s" ] && [ "$2" = ".[0] * .[1]" ]; then\n'
                 '  "' + str(root / "serena/bin/python") + '" "' + str(root / "configure-agent.py") +
                 '" --check-gateway-merge "$3" || exit $?\nfi\n')
    wrapper.write_text('#!/bin/sh\nexport LD_LIBRARY_PATH="' + str(root / "lib") +
                       '${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n'
                       'export FONTCONFIG_FILE="' + str(root / "fonts.conf") +
                       '"\n' + guard + 'exec "' + target + '" "$@"\n')
    wrapper.chmod(0o755)


def main():
    root = Path("/opt/sbx-dev")
    shutil.copy2(next(Path("/tmp").glob("uv-*/uvx")), root / "bin/uvx")
    lib = root / "lib"
    lib.mkdir()
    executables = root / "libexec"
    executables.mkdir()
    for name in ("fdfind", "fzf", "just", "shellcheck", "shfmt", "sqlite3", "redis-cli",
                 "tree", "wget", "ssh", "git-lfs", "zip", "unzip", "make", "gh", "jq", "rg"):
        shutil.copy2(shutil.which(name), executables / name)
    shutil.copy2(next(Path("/usr/lib/postgresql").glob("*/bin/psql")), executables / "psql")
    for path in list(root.rglob("*")):
        if not path.is_file() or lib in path.parents:
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        output = subprocess.run(["ldd", str(path)], capture_output=True, text=True).stdout
        for source in re.findall(r"=> (/\S+)", output):
            name = Path(source).name
            if name.startswith(("libc.so", "libm.so", "libpthread.so", "libdl.so", "librt.so", "ld-linux")):
                continue
            if not (lib / name).exists():
                shutil.copy2(source, lib / name, follow_symlinks=True)
    shutil.copytree("/usr/share/fonts/truetype", root / "fonts")
    (root / "fonts.conf").write_text('<fontconfig><dir>/opt/sbx-dev/fonts</dir><cachedir>/tmp/sbx-dev-font-cache</cachedir></fontconfig>\n')
    targets = {path.name: str(path) for path in executables.iterdir()}
    targets.update(fd=str(executables / "fdfind"), serena=str(root / "serena/bin/serena"),
                   pnpm=str(root / "npm/bin/pnpm"), corepack=str(root / "npm/bin/corepack"),
                   **{"playwright-cli": str(root / "npm/bin/playwright-cli")})
    for name, target in targets.items():
        write_wrapper(root, name, target)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check the CLI version from native SBX JSON without requiring a running daemon."""
import json
import re
import sys


try:
    version = json.load(sys.stdin)["client"]["version"]
except (ValueError, KeyError, TypeError):
    sys.exit("sbx-dev: Docker Sandboxes 0.49.2+ is required (invalid version document)")

match = re.fullmatch(
    r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][a-zA-Z0-9.+-]+)?",
    version,
) if isinstance(version, str) else None
if not match or tuple(map(int, match.groups()[:3])) < (0, 49, 2) or (
    match.groups()[:3] == ("0", "49", "2") and (match[4] or "").startswith("-")
):
    sys.exit(f"sbx-dev: Docker Sandboxes 0.49.2+ is required (observed: {version!r})")

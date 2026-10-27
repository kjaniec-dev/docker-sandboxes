#!/usr/bin/env python3
"""Check the CLI version from native SBX JSON without requiring a running daemon."""
import json
import re
import sys


FLOOR = (0, 50, 0)
REQUIRED = "sbx-dev: Docker Sandboxes {}.{}.{}+ is required".format(*FLOOR)

try:
    version = json.load(sys.stdin)["client"]["version"]
except (ValueError, KeyError, TypeError):
    sys.exit(f"{REQUIRED} (invalid version document)")

match = re.fullmatch(
    r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][a-zA-Z0-9.+-]+)?",
    version,
) if isinstance(version, str) else None
if not match or tuple(map(int, match.groups()[:3])) < FLOOR or (
    tuple(map(int, match.groups()[:3])) == FLOOR and (match[4] or "").startswith("-")
):
    sys.exit(f"{REQUIRED} (observed: {version!r})")

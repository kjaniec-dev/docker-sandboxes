#!/usr/bin/env python3
"""Reject malformed agent maps whenever jq receives a protected config path.

Options and filter spelling belong to the official kits. Inspect resolved file
arguments instead of matching one invocation. Stdin-only input has no path; the
native smoke probe separately checks the installed official hook contract.
"""
import json
from pathlib import Path
import sys


def main():
    protected = {
        (Path.home() / relative).resolve(): key
        for relative, key in ((".gemini/config/mcp_config.json", "mcpServers"),
                              (".config/opencode/opencode.json", "mcp"))
    }
    for argument in sys.argv[1:]:
        key = None
        try:
            path = Path(argument).resolve()
            key = protected.get(path)
            if key is None or not path.exists():
                continue
            value = json.loads(path.read_text())
        except (OSError, ValueError) as exc:
            # Non-path arguments (including multiline filters) are jq's concern.
            if key is None:
                continue
            raise SystemExit(f"sbx-dev: cannot validate {path}: {exc}")
        if not isinstance(value, dict) or not isinstance(value.get(key, {}), dict):
            raise SystemExit(f"sbx-dev: expected {key} to be an object in {path}")


if __name__ == "__main__":
    main()

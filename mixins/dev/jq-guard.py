#!/usr/bin/env python3
"""Reject malformed agent maps whenever jq receives a protected config path.

Options and filter spelling belong to the official kits. The shell launcher
selects protected file identities before starting this validator. Stdin has no path; the
native smoke probe separately checks the installed official hook contract.
"""
import json
from pathlib import Path
import sys


def main():
    protected = {
        Path.home() / relative: key
        for relative, key in ((".gemini/config/mcp_config.json", "mcpServers"),
                              (".config/opencode/opencode.json", "mcp"))
    }
    for argument in sys.argv[1:]:
        key = None
        try:
            path = Path(argument)
            key = next((key for target, key in protected.items()
                        if target.exists() and path.samefile(target)), None)
            if key is None:
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

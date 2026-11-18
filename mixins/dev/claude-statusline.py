#!/usr/bin/env python3
"""Claude Code statusline: read one JSON object from stdin; never log payloads."""
import json
import sys


def render(data):
    model = data.get("model") or {}
    name = model.get("display_name") if isinstance(model, dict) else None
    context = data.get("context_window") or {}
    if not isinstance(context, dict):
        context = {}
    parts = [str(name) if name else "Claude"]
    used = context.get("used_percentage")
    remaining = context.get("remaining_percentage")
    if isinstance(used, (int, float)) and not isinstance(used, bool) and 0 <= used <= 100:
        parts.append(f"context {used:.0f}%")
    elif isinstance(remaining, (int, float)) and not isinstance(remaining, bool) and 0 <= remaining <= 100:
        parts.append(f"context {100 - remaining:.0f}%")
    size = context.get("context_window_size")
    if isinstance(size, int) and not isinstance(size, bool) and size > 0:
        parts.append(f"window {size // 1000}k")
    # Total session tokens and current context occupancy are distinct.
    # Never calculate usage from cost, disk, or sandbox memory.
    return " | ".join(parts)


def main():
    try:
        data = json.load(sys.stdin)
        if not isinstance(data, dict):
            raise ValueError("status payload must be an object")
        print(render(data))
    except (ValueError, TypeError, json.JSONDecodeError):
        print("Claude | context unavailable")
    return 0


if __name__ == "__main__":
    sys.exit(main())

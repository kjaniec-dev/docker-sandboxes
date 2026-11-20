#!/usr/bin/env python3
"""Claude Code statusline: read one JSON object from stdin; never log payloads."""
import json
import subprocess
import sys


def render(data):
    model = data.get("model") or {}
    name = model.get("display_name") if isinstance(model, dict) else None
    context = data.get("context_window") or {}
    if not isinstance(context, dict):
        context = {}
    parts = [str(name) if name else "Claude"]
    size = context.get("context_window_size")
    size = size if isinstance(size, int) and not isinstance(size, bool) and size > 0 else None
    usage = context.get("current_usage")
    keys = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
    if isinstance(usage, dict) and all(isinstance(usage.get(k), int) and not isinstance(usage[k], bool) and usage[k] >= 0 for k in keys):
        tokens = sum(usage[k] for k in keys)
        parts.append(f"context {tokens:,}/{size:,} tokens" if size else f"context {tokens:,} tokens")
    elif size:
        parts.append(f"window {size // 1000}k")
    used = context.get("used_percentage")
    remaining = context.get("remaining_percentage")
    if isinstance(used, (int, float)) and not isinstance(used, bool) and 0 <= used <= 100:
        parts.append(f"{used:.0f}%" if isinstance(usage, dict) else f"context {used:.0f}%")
    elif isinstance(remaining, (int, float)) and not isinstance(remaining, bool) and 0 <= remaining <= 100:
        parts.append(f"context {100 - remaining:.0f}%")
    # Total session tokens and current context occupancy are distinct.
    # Never calculate usage from cost, disk, or sandbox memory.
    return " | ".join(parts)


def main():
    try:
        payload = sys.stdin.read()
        data = json.loads(payload)
        if not isinstance(data, dict):
            raise ValueError("status payload must be an object")
        try:
            subprocess.run(["/usr/local/bin/sbx-claude-hook", "claude-status"], input=payload,
                           text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3, check=False)
        except (OSError, subprocess.TimeoutExpired):
            pass
        print(render(data))
    except (ValueError, TypeError, json.JSONDecodeError):
        print("Claude | context unavailable")
    return 0


if __name__ == "__main__":
    sys.exit(main())

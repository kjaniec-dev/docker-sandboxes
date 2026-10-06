#!/usr/bin/env python3
"""Verify completed model output; echoes, errors and incomplete turns fail."""
import json
from pathlib import Path
import sys


def response(agent, text):
    if agent in ("junie", "copilot"):
        return text.strip()
    events = [json.loads(line) for line in text.splitlines() if line.strip()]
    if agent == "claude":
        if any(e.get("type") == "result" and e.get("is_error") is True for e in events):
            return None
        results = [e["result"] for e in events if e.get("type") == "result" and e.get("is_error") is False]
        return results[-1].strip() if results else None
    if agent == "codex":
        if not any(e.get("type") == "turn.completed" for e in events) or any(e.get("type") in ("turn.failed", "error") for e in events):
            return None
        results = [e["item"]["text"] for e in events if e.get("type") == "item.completed" and e.get("item", {}).get("type") == "agent_message"]
        return results[-1].strip() if results else None
    if agent == "opencode":
        if any(e.get("type") == "error" for e in events) or not any(e.get("type") == "step_finish" and e.get("part", {}).get("reason") == "stop" for e in events):
            return None
        return "".join(e["part"]["text"] for e in events if e.get("type") == "text" and e.get("part", {}).get("type") == "text").strip()
    if agent == "antigravity":
        results = [e["response"] for e in events if e.get("status") == "SUCCESS"]
        return results[-1].strip() if results else None
    raise ValueError(f"Unsupported agent: {agent}")


if __name__ == "__main__":
    agent, expected, path = sys.argv[1:]
    if response(agent, Path(path).read_text()) != expected:
        raise SystemExit("smoke: model response was not a verified completed answer")

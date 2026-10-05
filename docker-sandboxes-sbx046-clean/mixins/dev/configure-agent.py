#!/usr/bin/env python3
"""Small compatibility adapter for sandbox-local MCP configuration.

Remote MCP servers belong to the SBX MCP gateway. Serena is different: it must
run inside the sandbox so it sees only the sandbox workspace. This script keeps
that one local server consistent across supported agent config formats.

It also adds an MCP-gateway fallback only where an official workload/mixin may
not yet wire the gateway itself. All writes are idempotent and preserve unrelated
user configuration.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

AGENT = os.environ.get("SBX_AGENT_KIND", "").strip().lower()
GATEWAY_URL = os.environ.get("MCP_GATEWAY_URL", "").strip()
GATEWAY_TOKEN = os.environ.get("MCP_SENTINEL_TOKEN_NAME", "").strip()
SERENA_CMD = ["serena", "start-mcp-server", "--context=ide-assistant", "--project-from-cwd"]


def run(*argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    try:
        value = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"sbx-dev: refusing to overwrite invalid JSON: {path}: {exc}")
    if not isinstance(value, dict):
        raise SystemExit(f"sbx-dev: expected a JSON object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as tmp:
            json.dump(value, tmp, indent=2, sort_keys=True)
            tmp.write("\n")
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def ensure_map(path: Path, key: str, entries: dict[str, Any]) -> None:
    value = load_json(path)
    current = value.get(key)
    if current is None:
        current = {}
    if not isinstance(current, dict):
        raise SystemExit(f"sbx-dev: expected {key} to be an object in {path}")
    current.update(entries)
    value[key] = current
    write_json(path, value)


def gateway_headers() -> dict[str, str]:
    if not GATEWAY_TOKEN:
        return {}
    return {"Authorization": f"Bearer {GATEWAY_TOKEN}"}


def configure_claude() -> None:
    if run("claude", "mcp", "get", "serena").returncode != 0:
        subprocess.run(
            ["claude", "mcp", "add", "serena", "--scope", "user", "--", *SERENA_CMD],
            check=True,
        )
    # Docker's official Claude mixin owns gateway registration.


def configure_codex() -> None:
    if run("codex", "mcp", "get", "serena", "--json").returncode != 0:
        subprocess.run(["codex", "mcp", "add", "serena", "--", *SERENA_CMD], check=True)
    # Docker's official Codex workload owns gateway registration.


def configure_opencode() -> None:
    path = Path.home() / ".config/opencode/opencode.json"
    entries: dict[str, Any] = {
        "serena": {
            "type": "local",
            "command": SERENA_CMD,
            "enabled": True,
        }
    }
    # The official OpenCode mixin normally adds the gateway. Keeping a fallback
    # here makes the local workload resilient while V3 integration is evolving.
    if GATEWAY_URL:
        entries["mcp-gateway"] = {
            "type": "remote",
            "url": GATEWAY_URL,
            "headers": gateway_headers(),
            "enabled": True,
        }
    ensure_map(path, "mcp", entries)


def configure_antigravity() -> None:
    path = Path.home() / ".gemini/config/mcp_config.json"
    entries: dict[str, Any] = {
        "serena": {
            "command": SERENA_CMD[0],
            "args": SERENA_CMD[1:],
            "disabled": False,
        }
    }
    if GATEWAY_URL:
        entries["mcp-gateway"] = {
            "serverUrl": GATEWAY_URL,
            "headers": gateway_headers(),
            "disabled": False,
        }
    ensure_map(path, "mcpServers", entries)


def configure_junie() -> None:
    path = Path.home() / ".junie/mcp/mcp.json"
    entries: dict[str, Any] = {
        "serena": {
            "command": SERENA_CMD[0],
            "args": SERENA_CMD[1:],
        }
    }
    if GATEWAY_URL:
        entries["mcp-gateway"] = {
            "url": GATEWAY_URL,
            "headers": gateway_headers(),
        }
    ensure_map(path, "mcpServers", entries)


def configure_copilot() -> None:
    path = Path.home() / ".copilot/mcp-config.json"
    entries: dict[str, Any] = {
        "serena": {
            "type": "stdio",
            "command": SERENA_CMD[0],
            "args": SERENA_CMD[1:],
            "tools": ["*"],
        }
    }
    if GATEWAY_URL:
        entries["mcp-gateway"] = {
            "type": "http",
            "url": GATEWAY_URL,
            "headers": gateway_headers(),
            "tools": ["*"],
        }
    ensure_map(path, "mcpServers", entries)


HANDLERS = {
    "claude": configure_claude,
    "codex": configure_codex,
    "opencode": configure_opencode,
    "antigravity": configure_antigravity,
    "junie": configure_junie,
    "copilot": configure_copilot,
}


def main() -> int:
    if not AGENT:
        print("sbx-dev: SBX_AGENT_KIND is empty; skipping agent-local MCP config", file=sys.stderr)
        return 0
    handler = HANDLERS.get(AGENT)
    if handler is None:
        print(f"sbx-dev: no local MCP adapter for agent {AGENT!r}; skipping", file=sys.stderr)
        return 0
    handler()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

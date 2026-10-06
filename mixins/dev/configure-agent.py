#!/usr/bin/env python3
"""Register sandbox-local Serena; official agent kits own remote MCP wiring."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib


def load_json(path):
    try:
        value = json.loads(path.read_text()) if path.exists() else {}
    except json.JSONDecodeError as exc:
        raise SystemExit(f"sbx-dev: invalid JSON in {path}: {exc}")
    if not isinstance(value, dict):
        raise SystemExit(f"sbx-dev: expected an object in {path}")
    return value


def register_json(path, key, server, gateway=None):
    value = load_json(path)
    servers = value.setdefault(key, {})
    if not isinstance(servers, dict):
        raise SystemExit(f"sbx-dev: expected {key} to be an object in {path}")
    existing = servers.get("serena")
    if "serena" in servers and (not isinstance(existing, dict) or
                               any(existing.get(k) != v for k, v in server.items())):
        raise SystemExit(f"sbx-dev: conflicting Serena config in {path}; reconcile it before launching")
    servers.setdefault("serena", server)
    if gateway:
        servers.setdefault("mcp-gateway", gateway)
    if path.exists() and value == load_json(path):
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check-gateway-merge":
        # Official jq merges replace malformed MCP arrays/null with the gateway map.
        # Validate these two agent files before their existing merge/move sequence.
        path = Path(sys.argv[2])
        for relative, key in ((".gemini/config/mcp_config.json", "mcpServers"),
                              (".config/opencode/opencode.json", "mcp")):
            if path == Path.home() / relative:
                value = load_json(path)
                if not isinstance(value.get(key, {}), dict):
                    raise SystemExit(f"sbx-dev: expected {key} to be an object in {path}")
        return
    agent = os.environ.get("SBX_AGENT_KIND", "")
    home = Path.home()
    command = ["serena", "start-mcp-server", f"--context={'codex' if agent == 'codex' else 'ide-assistant'}",
               "--project-from-cwd"]
    if agent == "codex":
        path = Path(os.environ.get("CODEX_HOME") or home / ".codex") / "config.toml"
        try:
            value = tomllib.loads(path.read_text()) if path.exists() else {}
        except tomllib.TOMLDecodeError as exc:
            raise SystemExit(f"sbx-dev: invalid TOML in {path}: {exc}")
        servers = value.get("mcp_servers", {})
        if not isinstance(servers, dict):
            raise SystemExit(f"sbx-dev: expected mcp_servers to be a table in {path}")
        if "serena" in servers:
            existing = servers["serena"]
            if not isinstance(existing, dict) or existing.get("command") != command[0] or existing.get("args") != command[1:]:
                raise SystemExit(f"sbx-dev: conflicting Serena config in {path}; reconcile it before launching")
        else:
            # Let Codex preserve its own TOML grammar, including inline maps and comments.
            env = os.environ.copy()
            if not env.get("CODEX_HOME"):
                env.pop("CODEX_HOME", None)
            subprocess.run(["codex", "mcp", "add", "serena", "--", *command], check=True, env=env)
        if os.environ.get("WORKSPACE_DIR"):
            workspace = Path(os.environ["WORKSPACE_DIR"]).resolve()
            destination = path.parent / "AGENTS.md"
            profile = workspace.parent / "AGENTS.md"
            if path.parent.resolve().is_relative_to(workspace):
                raise SystemExit("sbx-dev: Codex global configuration must be outside the mounted project")
            override = path.parent / "AGENTS.override.md"
            if override.exists() and override.read_text().strip():
                raise SystemExit(f"sbx-dev: Codex context overridden by {override}")
            if destination.exists() or destination.is_symlink():
                if not destination.is_symlink() or destination.resolve() != profile.resolve():
                    raise SystemExit(f"sbx-dev: conflicting Codex global instructions in {destination}")
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                # SBX materializes this composed profile after install hooks.
                destination.symlink_to(profile)
        return
    formats = {
        "claude": (".claude.json", "mcpServers", {"type": "stdio", "command": command[0], "args": command[1:]}),
        "opencode": (".config/opencode/opencode.json", "mcp", {"type": "local", "command": command, "enabled": True}),
        "antigravity": (".gemini/config/mcp_config.json", "mcpServers", {"command": command[0], "args": command[1:], "disabled": False}),
        "junie": (".junie/mcp/mcp.json", "mcpServers", {"command": command[0], "args": command[1:]}),
        "copilot": (".copilot/mcp-config.json", "mcpServers", {"type": "stdio", "command": command[0], "args": command[1:], "tools": ["*"]}),
    }
    if agent not in formats:
        raise SystemExit(f"sbx-dev: unsupported SBX_AGENT_KIND: {agent!r}")
    relative, key, server = formats[agent]
    gateway = None
    # Junie's official workload is the only supported kit without a gateway hook.
    if agent == "junie" and os.environ.get("MCP_GATEWAY_URL"):
        gateway = {"url": os.environ["MCP_GATEWAY_URL"], "headers": {
            "Authorization": f"Bearer {os.environ.get('MCP_SENTINEL_TOKEN_NAME', '')}"}}
    register_json(home / relative, key, server, gateway)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Reconcile local Serena and Junie JVM proxy settings from native SBX metadata."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
from urllib.parse import urlsplit


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


def configure_junie_proxy(home, environment):
    # Junie's OkHttp MCP transport uses Java's proxy selector, not HTTP_PROXY.
    # Configure the official jpackage launcher rather than replacing its entrypoint.
    options = []
    http = environment.get("HTTP_PROXY") or environment.get("http_proxy")
    for scheme, address in (("http", http), ("https", environment.get("HTTPS_PROXY")
                            or environment.get("https_proxy") or http)):
        if not address:
            continue
        try:
            proxy = urlsplit(address)
            if (proxy.scheme != "http" or not proxy.hostname or proxy.username
                    or proxy.password or proxy.query or proxy.fragment
                    or proxy.path not in ("", "/")
                    or any(c.isspace() or c in "\"'" for c in proxy.hostname)):
                raise ValueError()
            port = proxy.port or 80
        except ValueError:
            # Proxy URLs may contain credentials; never echo their value.
            raise SystemExit(f"sbx-dev: invalid native {scheme} proxy for Junie's JVM") from None
        options.extend((f"java-options=-D{scheme}.proxyHost={proxy.hostname}\n",
                        f"java-options=-D{scheme}.proxyPort={port}\n"))
    data = Path(environment.get("JUNIE_DATA") or home / ".local/share/junie")
    configs = sorted((data / "versions").glob("*/junie-app/lib/app/junie.cfg"))
    if options and not configs:
        raise SystemExit("sbx-dev: Junie JVM launcher configuration not found")
    begin, end = "# sbx-dev native proxy begin\n", "# sbx-dev native proxy end\n"
    for path in configs:
        original = path.read_text()
        before, separator, after = original.partition(begin)
        if separator:
            _, separator, after = after.partition(end)
            if not separator:
                raise SystemExit(f"sbx-dev: incomplete native proxy block in {path}")
        else:
            after = ""
        updated = before + after
        section = "[JavaOptions]\n"
        if section not in updated:
            raise SystemExit(f"sbx-dev: missing JavaOptions section in {path}")
        if options:
            updated = updated.replace(section, section + begin + "".join(options) + end, 1)
        if updated == original:
            continue
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(updated)
            os.chmod(temporary, path.stat().st_mode & 0o777)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def main():
    agent = os.environ.get("SBX_AGENT_KIND", "")
    home = Path.home()
    if agent == "junie":
        configure_junie_proxy(home, os.environ)
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
            if path.parent.resolve().is_relative_to(workspace):
                raise SystemExit("sbx-dev: Codex global configuration must be outside the mounted project")
            override = path.parent / "AGENTS.override.md"
            if override.exists() and override.read_text().strip():
                raise SystemExit(f"sbx-dev: Codex context overridden by {override}")
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

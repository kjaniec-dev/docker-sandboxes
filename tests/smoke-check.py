#!/usr/bin/env python3
"""Run inside a disposable sandbox: real tooling, Chromium, skills and MCP."""
import json
import os
import pty
from pathlib import Path
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.request


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, text=True, capture_output=True, timeout=90, **kwargs).stdout


def decode_rpc(raw):
    text = raw.decode()
    if text.lstrip().startswith("{"):
        return json.loads(text)
    for line in text.splitlines():
        if line.startswith("data:"):
            return json.loads(line[5:].strip())
    raise RuntimeError("MCP response contains no JSON-RPC message")


def gateway_call(url, headers, method, params, identity, session=None):
    headers = {**headers, "Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if session:
        headers["Mcp-Session-Id"] = session
        headers["MCP-Protocol-Version"] = "2025-03-26"
    message = {"jsonrpc": "2.0", "method": method, "params": params}
    if identity is not None:
        message["id"] = identity
    request = urllib.request.Request(url, json.dumps(message).encode(), headers, method="POST")
    with urllib.request.urlopen(request, timeout=40) as response:
        raw = response.read()
        result = decode_rpc(raw) if raw else {}
        check("error" not in result, f"MCP gateway rejected {method}: {result.get('error')}")
        return result.get("result", {}), response.headers.get("Mcp-Session-Id", session)


def check_gateway(config):
    url = config.get("url") or config.get("serverUrl")
    headers = config.get("http_headers", config.get("headers", {}))
    check(url, "No MCP gateway URL in the agent's effective configuration")
    _, session = gateway_call(url, headers, "initialize", {
        "protocolVersion": "2025-03-26", "capabilities": {},
        "clientInfo": {"name": "sbx-rewrite-smoke", "version": "1"}}, 1)
    gateway_call(url, headers, "notifications/initialized", {}, None, session)
    result, _ = gateway_call(url, headers, "tools/list", {}, 2, session)
    tools = result.get("tools", [])
    tool = next((item for item in tools if "resolve" in item["name"].lower()
                 and "library" in item["name"].lower()), None)
    check(tool, f"Context7 resolve-library tool not exposed through native gateway: {[t['name'] for t in tools]}")
    result, _ = gateway_call(url, headers, "tools/call", {
        "name": tool["name"], "arguments": {"libraryName": "react", "query": "React official documentation"}}, 3, session)
    check(not result.get("isError") and result.get("content"), "Context7 tool call failed")
    print("smoke-check: Context7 gateway call passed")


def check_serena(command, workspace):
    with tempfile.TemporaryFile() as errors:
        server = subprocess.Popen(command, cwd=workspace, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=errors, text=True, bufsize=1)
        try:
            def request(method, params, identity):
                message = {"jsonrpc": "2.0", "method": method, "params": params}
                if identity is not None:
                    message["id"] = identity
                server.stdin.write(json.dumps(message) + "\n")
                server.stdin.flush()
                if identity is None:
                    return {}
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline:
                    readable, _, _ = select.select([server.stdout], [], [], max(0, deadline - time.monotonic()))
                    if not readable:
                        break
                    line = server.stdout.readline()
                    check(line, "Serena stopped before its MCP response")
                    response = json.loads(line)
                    if response.get("id") == identity:
                        check("error" not in response, f"Serena RPC failed: {response.get('error')}")
                        return response["result"]
                raise RuntimeError("Serena MCP response timed out")
            request("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                    "clientInfo": {"name": "sbx-rewrite-smoke", "version": "1"}}, 1)
            request("notifications/initialized", {}, None)
            tools = request("tools/list", {}, 2)["tools"]
            check(any(tool["name"] == "find_symbol" for tool in tools), "Serena symbol navigation unavailable")
            result = request("tools/call", {"name": "find_symbol", "arguments": {
                "name_path_pattern": "smoke_symbol", "relative_path": "main.py"}}, 3)
            check(not result.get("isError") and "smoke_symbol" in json.dumps(result),
                  "Serena cannot find the mounted project's symbol: " + json.dumps(result)[:3000])
            print("smoke-check: sandbox-local Serena symbol lookup passed")
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


def check_junie_gateway():
    """Exercise Junie's actual JVM MCP transport, without making a model request."""
    logs = Path.home() / ".junie/logs"
    before = set(logs.glob("*.log"))
    master, slave = pty.openpty()
    process = subprocess.Popen(["junie", "--skip-update-check"], stdin=slave, stdout=slave,
                               stderr=slave, start_new_session=True)
    os.close(slave)
    try:
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            # Drain the terminal so startup output cannot block the client.
            readable, _, _ = select.select([master], [], [], 0)
            if readable:
                try:
                    os.read(master, 65536)
                except OSError:
                    pass
            content = "\n".join(path.read_text() for path in set(logs.glob("*.log")) - before)
            check("UnknownHostException: mcp-gateway.docker.internal" not in content,
                  "Junie's MCP client bypassed the native SBX proxy")
            if "Connected to MCP server 'mcp-gateway'" in content:
                print("smoke-check: actual Junie MCP gateway initialization passed")
                return
            check(process.poll() is None, "Junie exited before its MCP gateway initialized")
            time.sleep(0.2)
        raise RuntimeError("Junie's MCP gateway initialization timed out")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        os.close(master)


def check_gateway_merge_guard(path, key):
    original = path.read_bytes()
    try:
        with tempfile.TemporaryDirectory() as directory:
            fragment = Path(directory) / "gateway.json"
            fragment.write_text(json.dumps({key: {"mcp-gateway": {"url": "unused"}}}))
            for invalid in ([{"command": "user-server"}], None):
                bad = json.dumps({key: invalid})
                path.write_text(bad)
                result = subprocess.run(["sh", "-ec",
                    'jq -s \'.[0] * .[1]\' "$1" "$2" > "$1.tmp"; mv "$1.tmp" "$1"',
                    "gateway-hook", str(path), str(fragment)], capture_output=True, text=True, timeout=30)
                check(result.returncode != 0 and path.read_text() == bad,
                      "Official gateway merge destroyed malformed MCP configuration")
    finally:
        path.write_bytes(original)
        path.with_name(path.name + ".tmp").unlink(missing_ok=True)
    print("smoke-check: malformed MCP gateway merge rejected without data loss")


def main():
    agent, workspace = sys.argv[1:]
    os.chdir(workspace)
    command_name = "agy" if agent == "antigravity" else agent
    for tool in (command_name, "git", "gh", "curl", "wget", "ssh", "rg", "fd", "jq", "yq", "fzf",
                 "make", "just", "shellcheck", "shfmt", "docker", "node", "npm", "corepack", "pnpm",
                 "python3", "uv", "go", "gopls", "goimports", "golangci-lint", "staticcheck", "govulncheck",
                 "dlv", "playwright-cli", "psql", "sqlite3", "redis-cli", "java", "javac", "mvn", "gradle", "serena"):
        check(shutil.which(tool), f"Missing tool: {tool}")
    for argv in (("node", "--version"), ("python3", "--version"), ("uv", "--version"), ("go", "version"),
                 ("mvn", "--version"), ("gradle", "--version"), ("docker", "compose", "version"),
                 (command_name, "--help")):
        run(argv)
    # jemalloc-based rg builds crash when the kernel page size differs from the build (4K vs 16K on ARM64).
    run(["getconf", "PAGE_SIZE"])
    # Standalone workloads can resolve their distro rg before the shared mixin wrapper.
    check(shutil.which("rg") in ("/opt/sbx-dev/bin/rg", "/usr/bin/rg"),
          f"Unexpected ripgrep: {shutil.which('rg')}")
    run(["rg", "--version"])
    run(["rg", "--files"])
    check(re.match(r"(?:openjdk|java) 25(?:[. ]|$)", run(["java", "--version"])), "Java 25 required")
    check(re.match(r"javac 25(?:[. ]|$)", run(["javac", "--version"])), "javac 25 required")
    browser = '/opt/sbx-dev/npm/lib/node_modules/@playwright/cli/node_modules/playwright'
    run(["node", "-e", """
const {chromium} = require(process.argv[1]);
(async () => { const browser = await chromium.launch({headless:true});
try { const page=await browser.newPage(); await page.setContent('<h1>SBX Chromium</h1>');
if(await page.textContent('h1') !== 'SBX Chromium') throw Error('Browser DOM check failed');
} finally { await browser.close(); } })().catch(e=>{console.error(e);process.exit(1)});
""", browser], env={**os.environ, "LD_LIBRARY_PATH": "/opt/sbx-dev/lib", "FONTCONFIG_FILE": "/opt/sbx-dev/fonts.conf"})
    home = Path.home()
    paths = {
        "claude": (".claude.json", "mcpServers", ".claude/skills"),
        "codex": (".codex/config.toml", "mcp_servers", ".agents/skills"),
        "opencode": (".config/opencode/opencode.json", "mcp", ".config/opencode/skills"),
        "antigravity": (".gemini/config/mcp_config.json", "mcpServers", ".gemini/config/skills"),
        "junie": (".junie/mcp/mcp.json", "mcpServers", ".junie/skills"),
        "copilot": (".copilot/mcp-config.json", "mcpServers", ".copilot/skills"),
    }
    relative, key, skills = paths[agent]
    content = (home / relative).read_text()
    config = (tomllib.loads(content) if agent == "codex" else json.loads(content))[key]
    server = config["serena"]
    if agent in ("antigravity", "opencode"):
        check_gateway_merge_guard(home / relative, key)
    command = server["command"]
    command = command if isinstance(command, list) else [command, *server["args"]]
    check(command[0] == "serena", "Serena must run as sandbox-local stdio")
    for name in ("using-superpowers", "caveman", "playwright-cli"):
        matches = list((home / skills).glob(f"**/{name}/SKILL.md"))
        check(matches, f"Native shared skill missing: {name}")
        try:
            descriptor = os.open(matches[0], os.O_WRONLY)
        except OSError:
            pass
        else:
            os.close(descriptor)
            raise RuntimeError(f"Shared skill is writable: {name}")
    guidance = list(Path(workspace).parent.glob("*.md"))
    check(any("/usr/share/sandbox/kit/dev/dev-context.md" in path.read_text() for path in guidance), "Native common agent context missing")
    if agent == "codex":
        check((home / ".codex/AGENTS.md").resolve() == Path(workspace).parent / "AGENTS.md", "Codex global instruction discovery missing")
    print("smoke-check: tooling, Chromium, read-only native skills and context passed")
    check_serena(command, workspace)
    check_gateway(config["mcp-gateway"])
    if agent == "junie":
        check_junie_gateway()


if __name__ == "__main__":
    main()

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
from urllib.parse import urlsplit


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def check_lifecycle(stage, marker, token):
    check(stage in ("fresh", "restarted", "recreated"), f"Unknown lifecycle stage: {stage}")
    if stage == "restarted":
        check(marker.is_file() and not marker.is_symlink() and marker.read_text() == token,
              "Sandbox-local marker was lost or changed after restart")
    else:
        check(not marker.exists() and not marker.is_symlink(),
              f"Sandbox-local marker unexpectedly survived into {stage} sandbox")
        marker.write_text(token)
    print(f"smoke-check: sandbox-local marker {stage} passed")


def check_context(agent, workspace, home):
    native = {"claude": ".claude/CLAUDE.md", "codex": ".codex/AGENTS.md"}
    guidance = [home / native[agent]] if agent in native else list(Path(workspace).parent.glob("*.md"))
    check(any(path.is_file() and "/usr/share/sandbox/kit/dev/dev-context.md" in path.read_text()
              for path in guidance), "Native common agent context missing")


def check_workspace_ignore(workspace):
    check((Path(workspace) / ".sbx-host-ignored/marker").is_file(), "Host ignore fixture missing from workspace")
    for path, label in ((".worktrees/.sbx-ignore-probe", "worktrees"),
                        (".sbx-host-ignored/marker", "host ignore")):
        result = subprocess.run(["git", "-C", str(workspace), "check-ignore", "-q", "--", path],
                                text=True, capture_output=True, timeout=15)
        check(result.returncode == 0, f"Workspace lost {label} decision: {result.stderr}")
    print("smoke-check: workspace Git and host ignore decisions passed")


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
    data = Path(os.environ.get("JUNIE_DATA") or Path.home() / ".local/share/junie")
    cfg = data / "current/junie-app/lib/app/junie.cfg"
    check(cfg.is_file(), "Junie's native JVM launcher configuration is missing")
    settings = cfg.read_text().splitlines()
    http = os.environ.get("HTTP_PROXY") or os.environ.get("http_proxy")
    for scheme, address in (("http", http), ("https", os.environ.get("HTTPS_PROXY")
                            or os.environ.get("https_proxy") or http)):
        check(address, f"Native SBX {scheme} proxy is missing")
        proxy = urlsplit(address)
        check(f"java-options=-D{scheme}.proxyHost={proxy.hostname}" in settings
              and f"java-options=-D{scheme}.proxyPort={proxy.port or 80}" in settings,
              f"Junie's native {scheme} JVM settings differ from the SBX runtime proxy")
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
    # Run the installed official hook rather than a copied jq command. This catches
    # a future hook using stdin or another transport that a path guard cannot see.
    hooks = []
    for descriptor in Path("/usr/share/sandbox/kit").glob("*/kit.yaml"):
        if descriptor.parent.name == "dev":
            continue
        kit = json.loads(run(["yq", "-o=json", ".", str(descriptor)]))
        for capability in kit.get("capabilities", []):
            if capability.get("type") != "com.docker.sandbox/lifecycle@1":
                continue
            for hook in capability.get("config", {}).get("startup", []):
                command = hook.get("command", "")
                if "MCP_GATEWAY_URL" in command and path.name in command:
                    hooks.append(command)
    check(len(hooks) == 1, "Cannot identify the installed official gateway hook; review jq protection")
    original = path.read_bytes()
    try:
        for bad in ("{broken", "[]", json.dumps({key: [{"command": "user-server"}]}),
                    json.dumps({key: None})):
            path.write_text(bad)
            result = subprocess.run(["sh", "-ec", hooks[0]], capture_output=True, text=True, timeout=30)
            check(result.returncode != 0 and path.read_text() == bad,
                  "Installed official gateway hook destroyed malformed MCP configuration")
    finally:
        path.write_bytes(original)
        path.with_name(path.name + ".tmp").unlink(missing_ok=True)
    print("smoke-check: installed official gateway hook rejects malformed MCP without data loss")


def main():
    agent, workspace, stage, sandbox = sys.argv[1:]
    os.chdir(workspace)
    check_lifecycle(stage, Path.home() / ".sbx-smoke-lifecycle", sandbox)
    check_workspace_ignore(workspace)
    if agent == "claude" and os.environ.get("CLAUDE_CODE_USE_VERTEX") == "1":
        check(os.environ.get("CLAUDE_CODE_SKIP_VERTEX_AUTH") == "1", "Vertex must use host authentication")
        check(not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"), "Unexpected sandbox ADC override")
        check(not (Path.home() / ".config/gcloud/application_default_credentials.json").exists(),
              "ADC must remain host-only")
        check(re.fullmatch(r"sbx-cs-[A-Za-z0-9_-]+", os.environ.get("ANTHROPIC_AUTH_TOKEN", "")),
              "Vertex environment must contain only the native placeholder")
        print("smoke-check: host-only Vertex authentication and placeholder passed")
    command_name = "agy" if agent == "antigravity" else agent
    for tool in (command_name, "git", "gh", "curl", "wget", "ssh", "rg", "fd", "jq", "yq", "fzf",
                 "make", "just", "shellcheck", "shfmt", "docker", "node", "npm", "corepack", "pnpm",
                 "python3", "uv", "uvx", "go", "gopls", "goimports", "golangci-lint", "staticcheck", "govulncheck",
                 "dlv", "playwright-cli", "psql", "sqlite3", "redis-cli", "java", "javac", "mvn", "gradle", "serena"):
        check(shutil.which(tool), f"Missing tool: {tool}")
    for argv in (("node", "--version"), ("python3", "--version"), ("uv", "--version"),
                 ("uvx", "--version"), ("go", "version"),
                 ("mvn", "--version"), ("gradle", "--version"), ("docker", "compose", "version"),
                 (command_name, "--help")):
        run(argv)
    # Exercise the workload's distro rg, including on 16 KiB ARM64 kernels.
    run(["getconf", "PAGE_SIZE"])
    check(shutil.which("rg") == "/usr/bin/rg",
          f"Expected workload ripgrep: {shutil.which('rg')}")
    check(not Path("/opt/sbx-dev/bin/rg").exists() and not Path("/opt/sbx-dev/libexec/rg").exists(),
          "Shared mixin must not duplicate workload ripgrep")
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
    if agent == "antigravity":
        for directory in (home / ".gemini", home / ".gemini/config"):
            check(directory.stat().st_uid == os.getuid(), f"Antigravity config ancestor not agent-owned: {directory}")
            with tempfile.TemporaryFile(dir=directory):
                pass
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
    check_context(agent, workspace, home)
    print("smoke-check: tooling, Chromium, read-only native skills and context passed")
    check_serena(command, workspace)
    check_gateway(config["mcp-gateway"])
    if agent == "junie":
        check_junie_gateway()


if __name__ == "__main__":
    main()

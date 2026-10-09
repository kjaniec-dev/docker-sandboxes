#!/usr/bin/env python3
"""Exercise the local MCP adapter against disposable real configuration files."""
import json
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ADAPTER = Path(__file__).resolve().parents[1] / "mixins/dev/configure-agent.py"
FORMATS = {
    "claude": (".claude.json", "mcpServers"),
    "opencode": (".config/opencode/opencode.json", "mcp"),
    "antigravity": (".gemini/config/mcp_config.json", "mcpServers"),
    "junie": (".junie/mcp/mcp.json", "mcpServers"),
    "copilot": (".copilot/mcp-config.json", "mcpServers"),
}


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)

    def invoke(self, agent, extra=None):
        env = os.environ.copy()
        for key in ("CODEX_HOME", "WORKSPACE_DIR"):
            env.pop(key, None)
        return subprocess.run([sys.executable, str(ADAPTER)], capture_output=True, text=True,
                              env={**env, "HOME": str(self.home), "SBX_AGENT_KIND": agent,
                                   "MCP_GATEWAY_URL": "http://gateway.invalid/mcp",
                                   "MCP_SENTINEL_TOKEN_NAME": "test-token", **(extra or {})}, cwd=self.home)

    def fixture(self, name, value):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def test_json_preserves_official_gateway_and_other_settings(self):
        for agent, (name, key) in FORMATS.items():
            with self.subTest(agent=agent):
                original = {"preferences": {"theme": "dark"}, key: {
                    "other": {"command": "custom"}, "mcp-gateway": {"url": "official"}}}
                path = self.fixture(name, json.dumps(original))
                result = self.invoke(agent)
                self.assertEqual(result.returncode, 0, result.stderr)
                actual = json.loads(path.read_text())
                self.assertEqual(actual["preferences"], original["preferences"])
                self.assertEqual(actual[key]["other"], original[key]["other"])
                self.assertEqual(actual[key]["mcp-gateway"], original[key]["mcp-gateway"])
                self.assertIn("serena", actual[key])
                before = path.read_bytes()
                self.assertEqual(self.invoke(agent).returncode, 0)
                self.assertEqual(path.read_bytes(), before)

    def test_json_malformed_input_is_preserved(self):
        for agent, (name, key) in FORMATS.items():
            for bad in ("{broken", "[]", json.dumps({key: []}), json.dumps({key: None})):
                with self.subTest(agent=agent, bad=bad):
                    path = self.fixture(name, bad)
                    self.assertNotEqual(self.invoke(agent).returncode, 0)
                    self.assertEqual(path.read_text(), bad)

    def test_json_conflicting_serena_is_preserved(self):
        for agent, (name, key) in FORMATS.items():
            with self.subTest(agent=agent):
                original = json.dumps({key: {"serena": {"command": "custom-serena"}}})
                path = self.fixture(name, original)
                self.assertNotEqual(self.invoke(agent).returncode, 0)
                self.assertEqual(path.read_text(), original)

    def gateway_hook(self, name, fragment):
        # Exercise the shipped jq launcher and the official kits' merge/move sequence.
        tools = self.home / "tools"
        (tools / "bin").mkdir(parents=True, exist_ok=True)
        (tools / "libexec").mkdir(exist_ok=True)
        (tools / "serena/bin").mkdir(parents=True, exist_ok=True)
        if not (tools / "libexec/jq").exists():
            (tools / "libexec/jq").symlink_to(shutil.which("jq"))
            (tools / "serena/bin/python").symlink_to(sys.executable)
        shutil.copy2(ADAPTER, tools / "configure-agent.py")
        spec = importlib.util.spec_from_file_location("export_tools", ADAPTER.with_name("export-tools.py"))
        exporter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(exporter)
        exporter.write_wrapper(tools, "jq", str(tools / "libexec/jq"))
        frag = self.fixture("gateway.json", json.dumps(fragment))
        cfg = self.home / name
        return subprocess.run(["sh", "-ec", 'jq -s \'.[0] * .[1]\' "$1" "$2" > "$1.tmp"; mv "$1.tmp" "$1"',
                               "gateway-hook", str(cfg), str(frag)], capture_output=True, text=True,
                              env={**os.environ, "HOME": str(self.home),
                                   "PATH": str(tools / "bin") + os.pathsep + os.environ["PATH"]})

    def test_official_gateway_hook_preserves_malformed_mcp(self):
        for agent in ("antigravity", "opencode"):
            name, key = FORMATS[agent]
            for bad in ("{broken", "[]", json.dumps({key: [{"command": "user-server"}]}),
                        json.dumps({key: None})):
                with self.subTest(agent=agent, bad=bad):
                    path = self.fixture(name, bad)
                    result = self.gateway_hook(name, {key: {"mcp-gateway": {"url": "official"}}})
                    self.assertNotEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(path.read_text(), bad)

    def test_official_gateway_hook_merges_valid_config_and_other_jq_is_unchanged(self):
        for agent in ("antigravity", "opencode"):
            name, key = FORMATS[agent]
            original = {"preferences": {"theme": "dark"}, key: {"user-server": {"command": "custom"}}}
            path = self.fixture(name, json.dumps(original))
            result = self.gateway_hook(name, {key: {"mcp-gateway": {"url": "official"}}})
            self.assertEqual(result.returncode, 0, result.stderr)
            actual = json.loads(path.read_text())
            self.assertEqual(actual["preferences"], original["preferences"])
            self.assertEqual(actual[key]["user-server"], original[key]["user-server"])
            self.assertEqual(actual[key]["mcp-gateway"], {"url": "official"})
        unrelated = self.fixture("unrelated.json", '{"mcp": []}')
        result = self.gateway_hook("unrelated.json", {"mcp": {"example": True}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(unrelated.read_text()), {"mcp": {"example": True}})

    def test_codex_existing_local_server_is_preserved(self):
        original = ('model = "custom"\n[mcp_servers.remote]\nurl = "https://remote.invalid"\n'
                    '[mcp_servers.serena]\ncommand = "serena"\n'
                    'args = ["start-mcp-server", "--context=codex", "--project-from-cwd"]\n')
        path = self.fixture(".codex/config.toml", original)
        result = self.invoke("codex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_text(), original)

    def test_codex_ignores_inherited_configuration_and_workspace(self):
        original = ('[mcp_servers.serena]\ncommand = "serena"\n'
                    'args = ["start-mcp-server", "--context=codex", "--project-from-cwd"]\n')
        local = self.fixture(".codex/config.toml", original)
        inherited = self.fixture("inherited-codex/config.toml", "broken = [")
        with patch.dict(os.environ, {"CODEX_HOME": str(inherited.parent),
                                    "WORKSPACE_DIR": str(self.home / "inherited-project")}):
            result = self.invoke("codex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(local.read_text(), original)
        self.assertEqual(inherited.read_text(), "broken = [")
        self.assertFalse((local.parent / "AGENTS.md").is_symlink())

    def test_empty_codex_home_uses_agent_home(self):
        original = ('[mcp_servers.serena]\ncommand = "serena"\n'
                    'args = ["start-mcp-server", "--context=codex", "--project-from-cwd"]\n')
        path = self.fixture(".codex/config.toml", original)
        result = self.invoke("codex", {"CODEX_HOME": "", "PATH": "/nonexistent"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_text(), original)

    def test_codex_reads_native_context_through_global_discovery(self):
        workspace = self.home / "project"
        workspace.mkdir()
        self.fixture("AGENTS.md", "Read /usr/share/sandbox/kit/dev/dev-context.md\n")
        original = ('[mcp_servers.serena]\ncommand = "serena"\n'
                    'args = ["start-mcp-server", "--context=codex", "--project-from-cwd"]\n')
        self.fixture(".codex/config.toml", original)
        result = self.invoke("codex", {"WORKSPACE_DIR": str(workspace)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / ".codex/AGENTS.md").is_symlink())
        self.assertEqual((self.home / ".codex/AGENTS.md").resolve(), (self.home / "AGENTS.md").resolve())

    def test_codex_invalid_or_conflicting_config_is_preserved(self):
        for original in ('broken = [', '[mcp_servers.serena]\ncommand = "custom"\n',
                         'mcp_servers = []\n'):
            with self.subTest(original=original):
                path = self.fixture(".codex/config.toml", original)
                self.assertNotEqual(self.invoke("codex").returncode, 0)
                self.assertEqual(path.read_text(), original)


if __name__ == "__main__":
    unittest.main()

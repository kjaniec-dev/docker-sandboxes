"""Validate native public metadata and Junie JVM environment inheritance."""
import importlib.util
from pathlib import Path
import json
import tempfile
import os
import re
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "workloads/junie-dev/token-placeholder.py"
spec = importlib.util.spec_from_file_location("junie_placeholder", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


adapter_path = Path(__file__).resolve().parents[1] / "mixins/dev/configure-agent.py"


def entry(placeholder="sbx-cs-public"):
    return {"env": "JUNIE_API_KEY", "targets": ["junie.jetbrains.com", "ingrazzio-cloud-prod.labs.jb.gg"],
            "placeholder": placeholder, "secret": "must-never-return-this"}


class NativePlaceholderTests(unittest.TestCase):
    def resolve(self, *inventories):
        return patch.object(module.subprocess, "check_output", side_effect=[
            json.dumps({"custom_secrets": values}) for values in inventories])

    def test_sandbox_scope_wins_without_reading_global_scope(self):
        with self.resolve([entry("sbx-cs-scoped")]) as call:
            self.assertEqual(module.resolve("project"), "sbx-cs-scoped")
            self.assertEqual(call.call_args.args[0], ["sbx", "secret", "ls", "--sandbox", "project", "--json"])
            self.assertEqual(call.call_count, 1)

    def test_global_fallback_returns_only_public_placeholder(self):
        with self.resolve([], [entry()]) as call:
            self.assertEqual(module.resolve("project"), "sbx-cs-public")
            self.assertEqual(call.call_args.args[0], ["sbx", "secret", "ls", "--global", "--json"])

    def test_missing_or_wrong_host_is_rejected(self):
        wrong = entry()
        wrong["targets"] = ["junie.jetbrains.com"]
        for inventory in ([], [wrong]):
            with self.resolve([], inventory), self.assertRaises(ValueError):
                module.resolve("project")

    def test_ambiguous_and_non_placeholder_values_are_rejected(self):
        for inventory in ([entry(), entry("sbx-cs-other")], [entry("real-token")]):
            with self.resolve(inventory), self.assertRaises(ValueError):
                module.resolve("project")


class NativeJvmProxyTests(unittest.TestCase):
    def test_shared_mcp_setup_does_not_depend_on_or_modify_junie_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            config = home / ".local/share/junie/current/junie-app/lib/app/junie.cfg"
            for content in (None, "unrecognized future Junie launcher format\n"):
                with self.subTest(installed=content is not None):
                    if content is not None:
                        config.parent.mkdir(parents=True)
                        config.write_text(content)
                    result = subprocess.run([sys.executable, str(adapter_path)], text=True,
                        capture_output=True, env={**os.environ, "HOME": str(home),
                        "SBX_AGENT_KIND": "junie", "HTTP_PROXY": "http://gateway.docker.internal:3128",
                        "MCP_GATEWAY_URL": "http://mcp-gateway.docker.internal/mcp",
                        "MCP_SENTINEL_TOKEN_NAME": "public-sentinel"})
                    self.assertEqual(result.returncode, 0, result.stderr)
                    servers = json.loads((home / ".junie/mcp/mcp.json").read_text())["mcpServers"]
                    self.assertIn("serena", servers)
                    self.assertEqual(servers["mcp-gateway"]["url"],
                                     "http://mcp-gateway.docker.internal/mcp")
                    if content is not None:
                        self.assertEqual(config.read_text(), content)

    @unittest.skipUnless(shutil.which("java"), "Java required for JVM environment inheritance probe")
    def test_profile_proxy_options_reach_new_jvm_without_installed_junie_configs(self):
        # macOS exposes a java launcher even when no host JVM is installed.
        available = subprocess.run(["java", "-version"], capture_output=True, timeout=30,
            env={key: value for key, value in os.environ.items()
                 if key not in {"JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS"}})
        if available.returncode:
            self.skipTest("No working host JVM; native smoke probes the sandbox JVM")
        profile = adapter_path.parents[2] / "env/personal/junie.sbxenv.yaml"
        # Read this profile's folded scalar without adding a YAML dependency to offline tests.
        match = re.search(r"^  JAVA_TOOL_OPTIONS: >-\n((?:    [^\n]*\n?)+)",
                          profile.read_text(), re.MULTILINE)
        self.assertIsNotNone(match, "Junie profile must declare its JVM launch environment")
        options = " ".join(line.strip() for line in match[1].splitlines())
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(["java", "-XshowSettings:properties", "-version"],
                text=True, capture_output=True, cwd=temporary,
                env={**os.environ, "JAVA_TOOL_OPTIONS": options})
            self.assertEqual(result.returncode, 0, result.stderr)
            properties = dict(re.findall(r"^\s+([\w.]+) = (.*)$", result.stderr, re.MULTILINE))
            self.assertEqual(properties.get("http.proxyHost"), "gateway.docker.internal")
            self.assertEqual(properties.get("https.proxyHost"), "gateway.docker.internal")
            self.assertEqual(properties.get("http.proxyPort"), "3128")
            self.assertEqual(properties.get("https.proxyPort"), "3128")
            self.assertEqual(properties.get("javax.net.ssl.trustStore"),
                             "/opt/sbx-dev/java/lib/security/cacerts")


if __name__ == "__main__":
    unittest.main()

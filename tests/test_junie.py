"""Validate selection of public native metadata; actual tokens never leave SBX."""
import importlib.util
from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "workloads/junie-dev/token-placeholder.py"
spec = importlib.util.spec_from_file_location("junie_placeholder", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


adapter_path = Path(__file__).resolve().parents[1] / "mixins/dev/configure-agent.py"
adapter_spec = importlib.util.spec_from_file_location("junie_adapter", adapter_path)
adapter = importlib.util.module_from_spec(adapter_spec)
adapter_spec.loader.exec_module(adapter)


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
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.config = (self.home / ".local/share/junie/versions/3294.5"
                       / "junie-app/lib/app/junie.cfg")
        self.config.parent.mkdir(parents=True)
        self.original = ("[Application]\napp.mainclass=official.Main\n\n[JavaOptions]\n"
                         "java-options=-Djpackage.app-version=3294.5\n"
                         "java-options=-Xmx2g\n")
        self.config.write_text(self.original)

    def test_native_runtime_proxy_reaches_jvm_and_reconciles_without_clobbering(self):
        environment = {"HTTP_PROXY": "http://native-proxy.internal:4567",
                       "HTTPS_PROXY": "http://tls-proxy.internal:5678"}
        adapter.configure_junie_proxy(self.home, environment)
        actual = self.config.read_text()
        for option in ("http.proxyHost=native-proxy.internal", "http.proxyPort=4567",
                       "https.proxyHost=tls-proxy.internal", "https.proxyPort=5678"):
            self.assertIn("java-options=-D" + option + "\n", actual)
        self.assertIn("app.mainclass=official.Main\n", actual)
        self.assertIn("java-options=-Xmx2g\n", actual)
        before = self.config.read_bytes()
        adapter.configure_junie_proxy(self.home, environment)
        self.assertEqual(self.config.read_bytes(), before)
        adapter.configure_junie_proxy(self.home, {"http_proxy": "http://new-proxy.internal"})
        actual = self.config.read_text()
        self.assertNotIn("native-proxy.internal", actual)
        self.assertNotIn("tls-proxy.internal", actual)
        self.assertIn("java-options=-Dhttps.proxyHost=new-proxy.internal\n", actual)
        self.assertIn("java-options=-Dhttp.proxyPort=80\n", actual)
        adapter.configure_junie_proxy(self.home, {})
        self.assertEqual(self.config.read_text(), self.original)

    def test_malformed_proxy_fails_without_changing_launcher_or_leaking_credentials(self):
        for proxy in ("garbage", "http://proxy:bad", "https://proxy:443",
                      "http://name:private-password@proxy:4567", "http://bad host:4567"):
            with self.subTest(proxy=proxy):
                with self.assertRaisesRegex(SystemExit, "invalid native.*proxy") as error:
                    adapter.configure_junie_proxy(self.home, {"HTTP_PROXY": proxy})
                self.assertNotIn("private-password", str(error.exception))
                self.assertEqual(self.config.read_text(), self.original)

    def test_invalid_jvm_configuration_is_preserved(self):
        self.config.write_text("[Application]\napp.mainclass=official.Main\n")
        with self.assertRaisesRegex(SystemExit, "JavaOptions"):
            adapter.configure_junie_proxy(self.home, {"HTTP_PROXY": "http://proxy:4567"})
        self.assertEqual(self.config.read_text(), "[Application]\napp.mainclass=official.Main\n")


if __name__ == "__main__":
    unittest.main()

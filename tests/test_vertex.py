"""Client Claude uses only scoped, host-resolved Vertex placeholders."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def entry(**changes):
    return {
        "scope": "client-project",
        "env": "ANTHROPIC_AUTH_TOKEN",
        "kind": "command",
        "targets": ["aiplatform.eu.rep.googleapis.com", "europe-west1-aiplatform.googleapis.com"],
        "placeholder": "sbx-cs-public",
        "secret": "must-never-return-this",
        **changes,
    }


class VertexPlaceholderTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / "workloads/claude-dev/token-placeholder.py"
        self.assertTrue(path.is_file(), "Client Claude placeholder adapter is missing")
        spec = importlib.util.spec_from_file_location("vertex_placeholder", path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def resolve(self, entries, region="eu"):
        with patch.object(self.module.subprocess, "check_output", return_value=json.dumps({
            "custom_secrets": entries,
        })) as call:
            result = self.module.resolve("client-project", region)
        self.assertEqual(call.call_args.args[0], [
            "sbx", "secret", "ls", "--sandbox", "client-project", "--json",
        ])
        self.assertEqual(call.call_count, 1)
        return result

    def test_returns_only_public_placeholder_from_scoped_command_secret(self):
        self.assertEqual(self.resolve([entry()]), "sbx-cs-public")

    def test_global_region_requires_exact_global_vertex_host(self):
        self.assertEqual(self.resolve([entry(targets=["aiplatform.googleapis.com"])], "global"),
                         "sbx-cs-public")

    def test_multi_regions_use_rep_vertex_hosts(self):
        for region in ("eu", "us"):
            with self.subTest(region=region):
                try:
                    result = self.resolve([entry(targets=[f"aiplatform.{region}.rep.googleapis.com"])],
                                          region)
                except ValueError as error:
                    self.fail(f"Claude multi-region Vertex hostname rejected: {error}")
                self.assertEqual(result, "sbx-cs-public")

    def test_missing_ambiguous_wrong_scope_and_static_secrets_are_rejected(self):
        for entries in ([], [entry(), entry(placeholder="sbx-cs-other")],
                        [entry(scope="global")], [entry(kind="value")]):
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.resolve(entries)

    def test_wrong_region_wildcards_and_nonvertex_targets_are_rejected(self):
        for targets in (["us-east5-aiplatform.googleapis.com"], ["eu-aiplatform.googleapis.com"],
                        ["*.aiplatform.googleapis.com"], ["aiplatform.*.rep.googleapis.com"],
                        ["*.googleapis.com"], ["aiplatform.eu.rep.googleapis.com", "oauth2.googleapis.com"]):
            with self.subTest(targets=targets), self.assertRaises(ValueError):
                self.resolve([entry(targets=targets)])

    def test_real_token_and_malformed_placeholder_are_rejected(self):
        for placeholder in ("real-token", "", "sbx-cs-public\n", "sbx-cs-public;command"):
            with self.subTest(placeholder=placeholder), self.assertRaises(ValueError):
                self.resolve([entry(placeholder=placeholder)])

    def test_invalid_region_and_inventory_are_explicit_errors(self):
        with self.assertRaises(ValueError):
            self.resolve([entry()], "eu/other")
        with patch.object(self.module.subprocess, "check_output", return_value='{"custom_secrets": null}'):
            with self.assertRaises(ValueError):
                self.module.resolve("client-project", "eu")


class VertexConfigurationTests(unittest.TestCase):
    def test_skip_google_auth_is_client_claude_only(self):
        self.assertIn('CLAUDE_CODE_SKIP_VERTEX_AUTH: "1"',
                      (ROOT / "env/client/claude.sbxenv.yaml").read_text())
        for path in (ROOT / "env/personal/claude.sbxenv.yaml",
                     ROOT / "env/client/copilot.sbxenv.yaml", ROOT / "env/common.sbxenv.yaml"):
            self.assertNotIn("CLAUDE_CODE_SKIP_VERTEX_AUTH", path.read_text())

    def test_vertex_mixin_no_longer_allows_google_credential_endpoints(self):
        content = (ROOT / "mixins/vertex/vertex.yaml").read_text()
        self.assertIn("aiplatform.googleapis.com:443", content)
        for host in ("oauth2.googleapis.com", "sts.googleapis.com", "iamcredentials.googleapis.com",
                     "cloudresourcemanager.googleapis.com", "serviceusage.googleapis.com"):
            self.assertNotIn(host, content)

    def test_vertex_mixin_covers_claude_multi_region_endpoints(self):
        content = (ROOT / "mixins/vertex/vertex.yaml").read_text()
        for region in ("eu", "us"):
            self.assertIn(f"aiplatform.{region}.rep.googleapis.com:443", content)


if __name__ == "__main__":
    unittest.main()

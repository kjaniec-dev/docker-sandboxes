"""Validate selection of public native metadata; actual tokens never leave SBX."""
import importlib.util
from pathlib import Path
import json
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "workloads/junie-dev/token-placeholder.py"
spec = importlib.util.spec_from_file_location("junie_placeholder", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


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


if __name__ == "__main__":
    unittest.main()

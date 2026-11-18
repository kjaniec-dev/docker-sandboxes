"""Offline checks for the Claude Code session statusline."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "mixins/dev/claude-statusline.py"
loader = importlib.machinery.SourceFileLoader("claude_statusline", str(PATH))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class ClaudeStatuslineTests(unittest.TestCase):
    def test_context_and_model(self):
        self.assertEqual(
            module.render({"model": {"display_name": "Claude"},
                           "context_window": {"used_percentage": 42, "context_window_size": 200000}}),
            "Claude | context 42% | window 200k",
        )

    def test_missing_data_is_not_invented(self):
        self.assertEqual(module.render({}), "Claude")

    def test_remaining_percent_fallback(self):
        self.assertEqual(module.render({"context_window": {"remaining_percentage": 70}}),
                         "Claude | context 30%")

    def test_invalid_percentage_is_not_reported(self):
        self.assertEqual(module.render({"context_window": {"used_percentage": 200}}), "Claude")


if __name__ == "__main__":
    unittest.main()

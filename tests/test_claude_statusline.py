"""Offline checks for the Claude Code session statusline."""
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import io

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
            "Claude | window 200k | context 42%",
        )

    def test_missing_data_is_not_invented(self):
        self.assertEqual(module.render({}), "Claude")

    def test_remaining_percent_fallback(self):
        self.assertEqual(module.render({"context_window": {"remaining_percentage": 70}}),
                         "Claude | context 30%")

    def test_invalid_percentage_is_not_reported(self):
        self.assertEqual(module.render({"context_window": {"used_percentage": 200}}), "Claude")

    def test_current_context_tokens_include_cache(self):
        self.assertEqual(module.render({"model": {"display_name": "Sonnet"}, "context_window": {
            "used_percentage": 20, "context_window_size": 200000,
            "current_usage": {"input_tokens": 1000, "cache_creation_input_tokens": 2000,
                              "cache_read_input_tokens": 37000}}}),
            "Sonnet | context 40,000/200,000 tokens | 20%")

    def test_narwhal_receives_payload_and_terminal_receives_status(self):
        payload = '{"model":{"display_name":"Sonnet"}}'
        output = io.StringIO()
        with patch('sys.stdin', io.StringIO(payload)), patch('sys.stdout', output), \
             patch.object(module.subprocess, 'run') as hook:
            module.main()
        self.assertEqual(output.getvalue(), 'Sonnet\n')
        self.assertEqual(hook.call_args.kwargs['input'], payload)


if __name__ == "__main__":
    unittest.main()

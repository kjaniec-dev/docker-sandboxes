import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'mixins/dev/codex-statusline.py'
spec = importlib.util.spec_from_file_location('codex_statusline', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CodexStatuslineTests(unittest.TestCase):
    def test_adds_defaults_without_changing_other_settings(self):
        original = 'model = "test"\n[tui]\nscreen_reader = true\n[other]\nvalue = 3\n'
        updated = module.configure(original)
        self.assertEqual(module.tomllib.loads(updated)['tui']['status_line'], module.ITEMS)
        self.assertEqual(module.tomllib.loads(updated)['other']['value'], 3)
        self.assertEqual(module.configure(updated), updated)

    def test_existing_statusline_is_preserved(self):
        original = '[tui]\nstatus_line = ["model"]\n'
        self.assertEqual(module.configure(original), original)

    def test_no_tui_table(self):
        self.assertEqual(module.tomllib.loads(module.configure('model = "test"\n'))['tui']['status_line'], module.ITEMS)

    def test_inline_tui_preserved(self):
        original = 'tui = { theme = "dark" }\n'
        self.assertEqual(module.configure(original), original)

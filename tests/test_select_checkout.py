import importlib.util
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

SELECTOR = Path(__file__).resolve().parents[1] / 'bin/select-checkout.py'
spec = importlib.util.spec_from_file_location('select_checkout', SELECTOR)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class SelectCheckoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.main = self.base / 'sandboxes'
        self.main.mkdir()
        subprocess.run(['git', '-C', str(self.main), 'init', '-q'], check=True)
        subprocess.run(['git', '-C', str(self.main), '-c', 'user.name=Test', '-c',
                        'user.email=test@example.invalid', 'commit', '--allow-empty', '-qm', 'initial'], check=True)
        self.worktree = self.main / '.worktrees' / 'feature'
        self.worktree.parent.mkdir()
        subprocess.run(['git', '-C', str(self.main), 'worktree', 'add', '-qb', 'feature', str(self.worktree)], check=True)

    def test_selects_registered_worktree_from_nested_directory(self):
        nested = self.worktree / 'nested'
        nested.mkdir()
        self.assertEqual(selector.select(self.main, nested), self.worktree)

    def test_selects_main_when_called_from_main(self):
        self.assertEqual(selector.select(self.main, self.main), self.main)

    def test_unrelated_project_keeps_invoked_checkout(self):
        unrelated = self.base / 'project'
        unrelated.mkdir()
        subprocess.run(['git', '-C', str(unrelated), 'init', '-q'], check=True)
        self.assertEqual(selector.select(self.main, unrelated), self.main)
        self.assertEqual(selector.select(self.worktree, unrelated), self.worktree)

    def test_rejects_forged_link_to_another_worktree(self):
        forged = self.main / '.worktrees' / 'forged'
        forged.mkdir()
        (forged / '.git').write_text((self.worktree / '.git').read_text())
        self.assertEqual(selector.select(self.main, forged), self.main)

    def test_rejects_symlinked_git_marker(self):
        forged = self.main / '.worktrees' / 'symlinked'
        forged.mkdir()
        (forged / '.git').symlink_to(self.worktree / '.git')
        self.assertEqual(selector.select(self.main, forged), self.main)

    def test_does_not_select_worktree_from_another_repo(self):
        other = self.base / 'other'
        other.mkdir()
        subprocess.run(['git', '-C', str(other), 'init', '-q'], check=True)
        self.assertEqual(selector.select(self.main, other), self.main)

    def test_installed_launcher_dispatches_to_selected_checkout(self):
        main_bin = self.main / 'bin'
        main_bin.mkdir()
        shutil.copy2(SELECTOR, main_bin / 'select-checkout.py')
        shutil.copy2(SELECTOR.with_name('sbx-dev'), main_bin / 'sbx-dev')
        (main_bin / 'opencode-sbx').symlink_to('sbx-dev')
        worktree_bin = self.worktree / 'bin'
        worktree_bin.mkdir()
        target = worktree_bin / 'opencode-sbx'
        target.write_text('#!/bin/sh\nprintf "selected:%s:%s\\n" "$1" "$2"\n')
        target.chmod(0o755)
        result = subprocess.run([str(main_bin / 'opencode-sbx'), '--model', 'literal value'],
                                cwd=self.worktree, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'selected:--model:literal value\n')


if __name__ == '__main__':
    unittest.main()

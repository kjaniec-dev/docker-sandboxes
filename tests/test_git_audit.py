"""Exercise Git metadata auditing with real, isolated Git configurations."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "bin/audit-git.py"


class GitAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.repo = self.base / "project with spaces\nand newline"
        self.repo.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME="Audit Test", GIT_AUTHOR_EMAIL="audit@example.invalid",
                        GIT_COMMITTER_NAME="Audit Test", GIT_COMMITTER_EMAIL="audit@example.invalid")
        self.git("init", "--quiet", "--template=")
        self.config = self.repo / ".git/config"
        self.original = self.config.read_bytes()

    def git(self, *args):
        result = subprocess.run(["git", "-C", str(self.repo), *args], env=self.env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def setting(self, key, value):
        self.git("config", "--file", str(self.config), key, value)

    def audit(self, *args, cwd=None):
        return subprocess.run([sys.executable, str(AUDIT), *(args or (str(self.repo),))],
                              cwd=cwd or self.repo, env=self.env, text=True, capture_output=True)

    def assert_rejected(self, result, diagnostic):
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn(diagnostic, result.stderr)

    def test_ext_transport_remote_urls_are_rejected_without_execution(self):
        marker = self.base / "must-not-run"
        for key in ("remote.origin.url", "remote.origin.pushurl"):
            with self.subTest(key=key):
                self.config.write_bytes(self.original)
                self.setting(key, f"ext::sh -c 'touch {marker}'")
                self.assert_rejected(self.audit(), "prohibited setting")
                self.assertFalse(marker.exists())
                self.assertNotIn(str(marker), self.audit().stderr)

    def test_ext_url_rewrite_base_is_checked_in_the_key(self):
        for variable in ("insteadOf", "pushInsteadOf"):
            with self.subTest(variable=variable):
                self.config.write_bytes(self.original)
                self.setting(f"URL.ext::sh -c attack.{variable}", "https://example.invalid/")
                self.assert_rejected(self.audit(), "prohibited setting")

    def test_normal_urls_and_rewrites_remain_usable(self):
        for key, value in (
            ("remote.origin.url", "https://example.invalid/project.git"),
            ("remote.origin.pushurl", "git@example.invalid:project.git"),
            ("url.ssh://git@example.invalid/.insteadOf", "https://example.invalid/"),
            ("url.https://example.invalid/ext::path.pushInsteadOf", "short:"),
            ("submodule.lib.update", "checkout"),
            ("sendemail.smtpServer", "smtp.example.invalid"),
            ("sendemail.work.smtpServer", "smtp.example.invalid"),
        ):
            self.setting(key, value)
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_additional_command_settings_are_rejected(self):
        for key, value in (
            ("submodule.lib.update", "!touch /must-not-run"),
            ("sendemail.sendmailCmd", "touch /must-not-run"),
            ("sendemail.work.sendmailCmd", "touch /must-not-run"),
            ("sendemail.smtpServer", "/tmp/sendmail"),
            ("sendemail.work.smtpServer", "/tmp/sendmail"),
            ("man.custom.cmd", "touch /must-not-run"),
            ("man.custom.path", "/tmp/man"),
            ("browser.custom.cmd", "touch /must-not-run"),
            ("browser.custom.path", "/tmp/browser"),
            ("init.templateDir", "/tmp/templates"),
            ("remote.origin.vcs", "custom-helper"),
            ("remote.origin.url", "helper::address"),
            ("remote.origin.pushurl", "EXT::command"),
            ("url.helper::address.insteadOf", "short:"),
            ("url.EXT::command.insteadOf", "short:"),
            ("protocol.ext.allow", "never"),
            ("protocol.Ext.allow", "always"),
            ("protocol.https.allow", "never"),
            ("sendemail.work.annotateCmd", "touch /must-not-run"),
            ("protocol.ext.allow", "always"),
            ("protocol.ext.allow", "user"),
            ("protocol.allow", "always"),
            ("protocol.allow", "user"),
        ):
            with self.subTest(key=key, value=value):
                self.config.write_bytes(self.original)
                self.setting(key, value)
                self.assert_rejected(self.audit(), "prohibited setting")

    def add_external_worktree(self):
        self.git("commit", "--quiet", "--allow-empty", "-m", "initial")
        worktree = self.base / "outside linked checkout"
        self.git("worktree", "add", "--quiet", "--detach", str(worktree))
        return worktree, next((self.repo / ".git/worktrees").iterdir())

    def test_main_checkout_accepts_external_linked_worktree_backpointer(self):
        worktree, admin = self.add_external_worktree()
        # Even an unavailable linked checkout is a valid administrative state.
        (admin / "gitdir").write_text(str(worktree / "unavailable/.git") + "\n")
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_external_backpointer_does_not_skip_local_worktree_config(self):
        _, admin = self.add_external_worktree()
        (admin / "config.worktree").write_text("[core]\n fsmonitor = attack\n")
        self.assert_rejected(self.audit(), "core.fsmonitor")

    def test_backpointer_target_is_never_audited(self):
        worktree, _ = self.add_external_worktree()
        (worktree / ".git").write_text("untrusted backpointer target contents\n")
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_forward_routing_still_rejects_external_paths(self):
        module = self.repo / ".git/modules/lib"
        module.mkdir(parents=True)
        for name in ("gitdir", "commondir"):
            with self.subTest(name=name):
                path = module / name
                path.write_text(str(self.base) + "\n")
                self.assert_rejected(self.audit(), "routing escapes")
                path.unlink()

    def test_stale_commondir_has_explicit_diagnostic(self):
        admin = self.repo / ".git/worktrees/stale"
        admin.mkdir(parents=True)
        for target in ("../../missing-common\n", "", "../../config\n"):
            with self.subTest(target=target):
                (admin / "commondir").write_text(target)
                self.assert_rejected(self.audit(), "stale commondir target")

    def test_hook_subdirectories_are_benign(self):
        disabled = self.repo / ".git/hooks/disabled"
        disabled.mkdir(parents=True)
        (disabled / "pre-commit").write_text("#!/bin/sh\nexit 0\n")
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_actual_hooks_and_hook_symlinks_still_fail_closed(self):
        hooks = self.repo / ".git/hooks"
        hooks.mkdir()
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 0\n")
        self.assert_rejected(self.audit(), "non-sample Git hook")
        hook.unlink()
        hook.symlink_to(self.base, target_is_directory=True)
        self.assert_rejected(self.audit(), "symlink")

    def test_hook_subdirectory_symlinks_still_fail_closed(self):
        disabled = self.repo / ".git/hooks/disabled"
        disabled.mkdir(parents=True)
        (disabled / "link").symlink_to(self.base)
        self.assert_rejected(self.audit(), "symlink")

    def test_discover_identity_returns_unambiguous_json_and_detects_replacement(self):
        nested = self.repo / "nested"
        nested.mkdir()
        result = self.audit("--discover-identity", cwd=nested)
        self.assertEqual(result.returncode, 0, result.stderr)
        root, identity = json.loads(result.stdout)
        self.assertEqual(root, str(self.repo))
        self.assertRegex(identity, r"^[0-9]+:[0-9]+$")
        self.assertEqual(self.audit(root, identity).returncode, 0)
        (self.repo / ".git").rename(self.repo / "original.git")
        self.git("init", "--quiet", "--template=")
        self.assert_rejected(self.audit(root, identity), "replaced")

    def test_discover_identity_audits_before_printing(self):
        self.setting("core.fsmonitor", "attack")
        result = self.audit("--discover-identity")
        self.assert_rejected(result, "core.fsmonitor")
        self.assertEqual(result.stdout, "")

    def test_quarantine_preserves_metadata_and_blocks_discovery(self):
        self.setting("core.fsmonitor", "attack")
        original = self.config.read_bytes()
        result = self.audit("--quarantine", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.repo / ".git").exists())
        quarantined = list(self.repo.glob(".git.sbx-quarantine-*"))
        self.assertEqual(len(quarantined), 1)
        self.assertEqual((quarantined[0] / "config").read_bytes(), original)
        for option in ("--discover", "--discover-identity"):
            with self.subTest(option=option):
                self.assert_rejected(self.audit(option), "quarantined Git metadata present")

    def test_discovery_rejects_quarantine_marker_even_with_active_git(self):
        (self.repo / ".git.sbx-quarantine-existing").mkdir()
        self.assert_rejected(self.audit("--discover-identity"), "quarantined Git metadata present")

    def test_worktrees_directory_accepts_genuine_local_link(self):
        # The worktree-link policy deliberately accepts only single-line paths.
        plain = self.base / "project with spaces"
        self.repo.rename(plain)
        self.repo = plain
        self.git("commit", "--quiet", "--allow-empty", "-m", "initial")
        worktree = self.repo / ".worktrees/review"
        self.git("worktree", "add", "--quiet", "--detach", str(worktree))
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_worktrees_directory_accepts_nested_repositories_at_any_depth(self):
        for relative in ("spike repo", "group/arbitrary/deep-repo",
                         "spike repo/.worktrees/another repo", "spike repo/group/child"):
            nested = self.repo / ".worktrees" / relative
            subprocess.run(["git", "init", "--quiet", "--template=", str(nested)],
                           env=self.env, check=True, capture_output=True)
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nested_repository_cannot_hide_descendant_metadata(self):
        outer = self.repo / ".worktrees/independent"
        child = outer / "group/child"
        for nested in (outer, child):
            subprocess.run(["git", "init", "--quiet", "--template=", str(nested)],
                           env=self.env, check=True, capture_output=True)
        (outer / "source-link").symlink_to(self.base / "not-present")
        config = child / ".git/config"
        original = config.read_bytes()
        config.write_bytes(original + b"\n[core]\nfsmonitor = attack\n")
        self.assert_rejected(self.audit(), "core.fsmonitor")
        config.write_bytes(original)
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.audit("--quarantine", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((child / ".git").exists())
        (saved,) = child.glob(".git.sbx-quarantine-*")
        self.assertEqual((saved / "config").read_bytes(), original)

    def test_quarantine_failure_does_not_leave_main_or_sibling_metadata_active(self):
        blocked = self.repo / ".worktrees/blocked"
        sibling = self.repo / ".worktrees/sibling"
        for nested in (blocked, sibling):
            subprocess.run(["git", "init", "--quiet", "--template=", str(nested)],
                           env=self.env, check=True, capture_output=True)
        self.addCleanup(blocked.chmod, 0o700)
        blocked.chmod(0o500)
        result = self.audit("--quarantine", str(self.repo))
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertFalse((self.repo / ".git").exists())
        self.assertFalse((sibling / ".git").exists())
        self.assertTrue((blocked / ".git").exists())
        self.assertIn("blocked/.git", result.stderr)

    def test_worktrees_directory_audits_nested_repository_config_and_hooks(self):
        nested = self.repo / ".worktrees/group/clone"
        subprocess.run(["git", "init", "--quiet", "--template=", str(nested)],
                       env=self.env, check=True, capture_output=True)
        config = nested / ".git/config"
        original = config.read_bytes()
        marker = self.base / "must-not-run"
        config.write_bytes(original + f"\n[core]\nfsmonitor = touch {marker}\n".encode())
        self.assert_rejected(self.audit(), "core.fsmonitor")
        self.assertFalse(marker.exists())
        config.write_bytes(original)
        hook = nested / ".git/hooks/pre-commit"
        hook.parent.mkdir(exist_ok=True)
        hook.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
        hook.chmod(0o755)
        self.assert_rejected(self.audit(), "non-sample Git hook")
        self.assertFalse(marker.exists())

    def test_worktrees_directory_rejects_incomplete_nested_repository(self):
        nested = self.repo / ".worktrees/group/clone/.git"
        nested.mkdir(parents=True)
        self.assert_rejected(self.audit(), "missing Git configuration")

    def test_quarantine_preserves_nested_repository_metadata(self):
        nested = self.repo / ".worktrees/group/arbitrary-repo"
        subprocess.run(["git", "init", "--quiet", "--template=", str(nested)],
                       env=self.env, check=True, capture_output=True)
        config = nested / ".git/config"
        original = config.read_bytes()
        result = self.audit("--quarantine", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.repo / ".git").exists())
        self.assertFalse((nested / ".git").exists())
        (saved,) = nested.glob(".git.sbx-quarantine-*")
        self.assertEqual((saved / "config").read_bytes(), original)
        self.assertIn(str(saved), result.stdout)
        (main_saved,) = self.repo.glob(".git.sbx-quarantine-*")
        main_saved.rename(self.repo / ".git")
        self.assert_rejected(self.audit(), "quarantined Git metadata present")

    def test_quarantine_descends_into_preexisting_quarantine_names(self):
        nested = self.repo / ".worktrees/.git.sbx-quarantine-fake/x"
        subprocess.run(["git", "init", "--quiet", "--template=", str(nested)],
                       env=self.env, check=True, capture_output=True)
        config = nested / ".git/config"
        marker = self.base / "must-not-run"
        original = config.read_bytes() + f"\n[core]\nfsmonitor = touch {marker}\n".encode()
        config.write_bytes(original)
        audit_result = self.audit()
        self.assert_rejected(audit_result, "quarantined Git metadata present")
        result = self.audit("--quarantine", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((nested / ".git").exists())
        (saved,) = nested.glob(".git.sbx-quarantine-*")
        self.assertEqual((saved / "config").read_bytes(), original)
        self.assertFalse(marker.exists())
        self.assertIn("do not run Git", audit_result.stderr)

    def test_quarantine_does_not_traverse_metadata_it_just_moved(self):
        nested = self.repo / ".worktrees/nested"
        subprocess.run(["git", "init", "--quiet", "--template=", str(nested)],
                       env=self.env, check=True, capture_output=True)
        stored = nested / ".git/objects/fixture/.git"
        stored.mkdir(parents=True)
        (stored / "config").write_text("stored object fixture\n")
        result = self.audit("--quarantine", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stderr)
        (saved,) = nested.glob(".git.sbx-quarantine-*")
        self.assertEqual((saved / "objects/fixture/.git/config").read_text(),
                         "stored object fixture\n")

    def test_worktrees_directory_rejects_bare_repository(self):
        nested = self.repo / ".worktrees/group/bare"
        nested.mkdir(parents=True)
        (nested / "HEAD").write_text("ref: refs/heads/main\n")
        (nested / "objects").mkdir()
        (nested / "refs").mkdir()
        self.assert_rejected(self.audit(), "bare repository in .worktrees")

    def test_worktrees_directory_rejects_symlinks(self):
        worktrees = self.repo / ".worktrees"
        worktrees.mkdir()
        (worktrees / "external").symlink_to(self.base, target_is_directory=True)
        self.assert_rejected(self.audit(), "symlink in .worktrees")

    def test_worktrees_directory_rejects_redirected_link(self):
        worktree = self.repo / ".worktrees/review"
        worktree.mkdir(parents=True)
        # A real directory outside the registry still must not be accepted.
        target = self.base / "external-admin"
        target.mkdir()
        (worktree / ".git").write_text(f"gitdir: {target}\n")
        self.assert_rejected(self.audit(), "worktree link does not point into")


if __name__ == "__main__":
    unittest.main()

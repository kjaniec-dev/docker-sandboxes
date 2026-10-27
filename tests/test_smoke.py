"""Prevent an echoed, unfinished or failed model turn from passing smoke."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("model_response", Path(__file__).with_name("model-response.py"))
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)

spec = importlib.util.spec_from_file_location("smoke_check", Path(__file__).with_name("smoke-check.py"))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.marker = Path(self.tmp.name) / "marker"

    def test_marker_survives_restart_and_is_absent_after_recreation(self):
        smoke.check_lifecycle("fresh", self.marker, "sandbox-token")
        self.assertEqual(self.marker.read_text(), "sandbox-token")
        smoke.check_lifecycle("restarted", self.marker, "sandbox-token")
        self.marker.unlink()
        smoke.check_lifecycle("recreated", self.marker, "sandbox-token")

    def test_missing_or_changed_marker_fails_restart(self):
        for content in (None, "wrong-token"):
            with self.subTest(content=content):
                if content is not None:
                    self.marker.write_text(content)
                with self.assertRaises(RuntimeError):
                    smoke.check_lifecycle("restarted", self.marker, "sandbox-token")

    def test_existing_marker_fails_fresh_and_recreated_checks(self):
        self.marker.write_text("sandbox-token")
        for stage in ("fresh", "recreated"):
            with self.subTest(stage=stage), self.assertRaises(RuntimeError):
                smoke.check_lifecycle(stage, self.marker, "sandbox-token")


class WorkspaceIgnoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.workspace = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", str(self.workspace)], check=True)
        (self.workspace / ".gitignore").write_text(".worktrees/\n")
        (self.workspace / ".worktrees").mkdir()
        fixture = self.workspace / ".sbx-host-ignored/marker"
        fixture.parent.mkdir()
        fixture.write_text("host ignore fixture\n")

    def test_workspace_preserves_both_repository_and_host_ignore_decisions(self):
        (self.workspace / ".git/info/exclude").write_text(".sbx-host-ignored/\n")
        smoke.check_workspace_ignore(self.workspace)

    def test_missing_host_ignore_is_rejected_even_when_worktrees_is_ignored(self):
        with self.assertRaisesRegex(RuntimeError, "host ignore"):
            smoke.check_workspace_ignore(self.workspace)

    def test_missing_worktrees_ignore_is_rejected(self):
        (self.workspace / ".gitignore").write_text("")
        (self.workspace / ".git/info/exclude").write_text(".sbx-host-ignored/\n")
        with self.assertRaisesRegex(RuntimeError, "worktrees"):
            smoke.check_workspace_ignore(self.workspace)


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.workspace = Path(self.tmp.name) / "workspace/project"
        self.workspace.mkdir(parents=True)

    def fixture(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def test_native_context_kits_use_agent_global_instructions(self):
        for agent, relative in (("claude", ".claude/CLAUDE.md"), ("codex", ".codex/AGENTS.md"),
                                ("opencode", ".config/opencode/AGENTS.md")):
            with self.subTest(agent=agent):
                self.fixture(self.home / relative, "Read /usr/share/sandbox/kit/dev/dev-context.md\n")
                smoke.check_context(agent, self.workspace, self.home)

    def test_ancestor_context_cannot_hide_missing_native_context(self):
        self.fixture(self.workspace.parent / "AGENTS.md", "Read /usr/share/sandbox/kit/dev/dev-context.md\n")
        for agent in ("claude", "codex", "opencode"):
            with self.subTest(agent=agent), self.assertRaises(RuntimeError):
                smoke.check_context(agent, self.workspace, self.home)

    def test_native_context_must_include_shared_dev_guidance(self):
        for agent, relative in (("claude", ".claude/CLAUDE.md"), ("codex", ".codex/AGENTS.md"),
                                ("opencode", ".config/opencode/AGENTS.md")):
            with self.subTest(agent=agent):
                self.fixture(self.home / relative, "Official agent context only\n")
                with self.assertRaises(RuntimeError):
                    smoke.check_context(agent, self.workspace, self.home)

    def test_remaining_kits_use_composed_ancestor_context(self):
        context = self.workspace.parent / "AGENTS.md"
        for agent in ("antigravity", "junie", "copilot"):
            with self.subTest(agent=agent):
                self.fixture(context, "Official agent context only\n")
                with self.assertRaises(RuntimeError):
                    smoke.check_context(agent, self.workspace, self.home)
                self.fixture(context, "Read /usr/share/sandbox/kit/dev/dev-context.md\n")
                smoke.check_context(agent, self.workspace, self.home)


class ResponseTests(unittest.TestCase):
    def test_codex_requires_completed_nonfailed_turn(self):
        answer = '{"type":"item.completed","item":{"type":"agent_message","text":"42"}}\n'
        self.assertIsNone(model.response("codex", answer))
        self.assertEqual(model.response("codex", answer + '{"type":"turn.completed"}\n'), "42")
        self.assertIsNone(model.response("codex", answer + '{"type":"turn.completed"}\n{"type":"turn.failed"}\n'))

    def test_claude_rejects_echo_and_any_failed_result(self):
        self.assertIsNone(model.response("claude", '{"type":"user","message":"42"}\n'))
        answer = '{"type":"result","is_error":false,"result":"42"}\n'
        self.assertEqual(model.response("claude", answer), "42")
        self.assertIsNone(model.response("claude", answer + '{"type":"result","is_error":true,"result":"error"}\n'))

    def test_opencode_rejects_unfinished_or_failed_step(self):
        answer = '{"type":"text","part":{"type":"text","text":"42"}}\n'
        self.assertIsNone(model.response("opencode", answer))
        answer += '{"type":"step_finish","part":{"reason":"stop"}}\n'
        self.assertEqual(model.response("opencode", answer), "42")
        self.assertIsNone(model.response("opencode", answer + '{"type":"error"}\n'))

    def test_antigravity_requires_successful_result(self):
        self.assertIsNone(model.response("antigravity", '{"status":"ERROR","response":"42"}\n'))
        self.assertEqual(model.response("antigravity", '{"status":"SUCCESS","response":"42"}\n'), "42")

    def test_text_mode_checks_entire_answer(self):
        for agent in ("junie", "copilot"):
            self.assertEqual(model.response(agent, "42\n"), "42")
            self.assertNotEqual(model.response(agent, "Calculate 20 + 22.\n42\n"), "42")

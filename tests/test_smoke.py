"""Prevent an echoed, unfinished or failed model turn from passing smoke."""
import importlib.util
from pathlib import Path
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

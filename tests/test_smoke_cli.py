"""Run the real smoke orchestration against the external SBX 0.48 CLI contract."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
NAME = "smoke-personal-codex-0123456789"


class SmokeCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sbx smoke cli ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.tools = self.base / "tools"
        self.tools.mkdir()
        self.log = self.base / "commands.jsonl"
        self.state = self.base / "state.json"
        self.state.write_text(json.dumps({"exists": False, "running": False, "generation": 0}))
        # Control only the random name, so an occupied-name fixture can be exact.
        (self.tools / "uuid.py").write_text(
            'from types import SimpleNamespace\ndef uuid4():\n    return SimpleNamespace(hex="0123456789abcdef")\n'
        )
        stub = self.tools / "sbx"
        stub.write_text("#!/usr/bin/env python3\n" + '''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["SBX_TEST_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
if "--detached" in args or "--auto-approve" in args:
    sys.exit("removed SBX flag")
path = Path(os.environ["SBX_TEST_STATE"])
state = json.loads(path.read_text())
name = "smoke-personal-codex-0123456789"
scenario = os.environ.get("SBX_TEST_SCENARIO", "normal")
if args == ["ls", "--json"]:
    if state.get("removal_succeeded") and scenario == "post-remove-inventory-error":
        print("[]")
        sys.exit(23)
    elif state.get("removal_succeeded") and scenario == "post-remove-inventory-malformed":
        print(os.environ["SBX_TEST_INVENTORY"])
    elif state.get("removal_failed") and scenario == "create-fails-inventory-error":
        print("[]")
        sys.exit(23)
    elif state.get("removal_failed") and scenario == "create-fails-inventory-malformed":
        print(os.environ["SBX_TEST_INVENTORY"])
    elif scenario == "malformed":
        print(os.environ["SBX_TEST_INVENTORY"])
    else:
        occupied = scenario == "occupied" or state["exists"]
        print(json.dumps([{"name": name}] if occupied else []))
elif args[:2] == ["env", "run"]:
    if "--detach" not in args or "--force" not in args:
        sys.exit("smoke provisioning requires --detach --force")
    if args[args.index("--name") + 1] != name:
        sys.exit("unexpected sandbox name")
    workspace = next(arg.removeprefix("workspace=") for arg in args if arg.startswith("workspace="))
    if not Path(workspace, ".git").is_dir():
        sys.exit("workspace was not initialized")
    state["workspace"] = workspace
    if scenario.startswith("create-fails-"):
        if scenario == "create-fails-retained":
            state.update(exists=True, running=True)
        path.write_text(json.dumps(state))
        sys.exit(17)
    if not state["exists"]:
        state["generation"] += 1
    state.update(exists=True, running=True)
elif args == ["stop", name]:
    if not state["running"]:
        sys.exit("cannot stop a sandbox that is not running")
    state["running"] = False
elif args[:2] == ["env", "rm"]:
    if "--force" not in args or args[args.index("--name") + 1] != name:
        sys.exit("unexpected removal")
    if not state["exists"] or scenario == "create-fails-retained":
        state["removal_failed"] = True
        path.write_text(json.dumps(state))
        sys.exit(1)
    if scenario != "retained":
        state.update(exists=False, running=False)
    state["removal_succeeded"] = True
elif args[:3] == ["exec", "-i", name]:
    if not state["running"] or args[3:6] != ["/opt/sbx-dev/serena/bin/python", "-", "codex"]:
        sys.exit("unexpected infrastructure check")
    sys.stdin.read()
else:
    sys.exit("unexpected SBX command: " + repr(args))
path.write_text(json.dumps(state))
''')
        stub.chmod(0o755)
        self.environ = dict(os.environ)
        for key in ("XDG_CONFIG_HOME", "SBX_SMOKE_KEEP_ON_FAILURE", "SBX_SMOKE_MODEL", "SBX_TEST_SCENARIO", "SBX_TEST_INVENTORY"):
            self.environ.pop(key, None)
        self.environ.update(
            HOME=str(self.base / "home"),
            PATH=str(self.tools) + os.pathsep + os.environ["PATH"],
            PYTHONPATH=str(self.tools),
            TMPDIR=str(self.base),
            SBX_PROFILE="personal",
            SBX_SMOKE_LOG_DIR=str(self.base / "logs"),
            SBX_TEST_LOG=str(self.log),
            SBX_TEST_STATE=str(self.state),
        )

    def run_smoke(self, **env):
        return subprocess.run(
            ["bash", str(ROOT / "tests/smoke.sh"), "codex"],
            env=self.environ | env, text=True, capture_output=True, timeout=30,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_fresh_restart_recreation_and_final_cleanup_use_048_contract(self):
        result = self.run_smoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertEqual([call[:2] for call in calls], [
            ["ls", "--json"], ["env", "run"], ["exec", "-i"],
            ["stop", NAME], ["env", "run"], ["exec", "-i"],
            ["env", "rm"], ["ls", "--json"], ["env", "run"],
            ["exec", "-i"], ["env", "rm"],
        ])
        checks = [call for call in calls if call[:2] == ["exec", "-i"]]
        self.assertEqual([call[-2] for call in checks], ["fresh", "restarted", "recreated"])
        for call in calls:
            if call[:2] == ["env", "run"]:
                self.assertIn("--detach", call)
                self.assertIn("--force", call)
                self.assertIn(str(ROOT / "env/personal/codex.sbxenv.yaml"), call)
                self.assertIn(str(ROOT / "env/common.sbxenv.yaml"), call)
        state = json.loads(self.state.read_text())
        self.assertEqual(state["generation"], 2)
        self.assertFalse(state["exists"])
        self.assertFalse(Path(state["workspace"]).exists())
        self.assertIn("smoke: PASS personal/codex", result.stdout)

    def test_malformed_inventory_never_creates_or_removes_a_sandbox(self):
        for inventory in ('not-json', 'null', '{}', '{"sandboxes": []}', '[{}]', '[null]', '[{"name": 42}]'):
            with self.subTest(inventory=inventory):
                self.log.unlink(missing_ok=True)
                result = self.run_smoke(SBX_TEST_SCENARIO="malformed", SBX_TEST_INVENTORY=inventory)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.calls(), [["ls", "--json"]])

    def test_creation_failure_cleans_workspace_when_failed_removal_confirms_absence(self):
        result = self.run_smoke(SBX_TEST_SCENARIO="create-fails-absent")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        state = json.loads(self.state.read_text())
        self.assertFalse(state["exists"])
        self.assertFalse(Path(state["workspace"]).exists())
        self.assertEqual([call[:2] for call in self.calls()], [
            ["ls", "--json"], ["env", "run"], ["env", "rm"], ["ls", "--json"],
        ])
        self.assertIn("smoke: creation failed", result.stderr)
        self.assertNotIn("smoke: cleanup failed", result.stderr)

    def test_failed_removal_retains_workspace_when_sandbox_still_exists(self):
        result = self.run_smoke(SBX_TEST_SCENARIO="create-fails-retained")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual([call[:2] for call in self.calls()], [
            ["ls", "--json"], ["env", "run"], ["env", "rm"], ["ls", "--json"],
        ])
        state = json.loads(self.state.read_text())
        self.assertTrue(state["exists"])
        self.assertTrue(Path(state["workspace"]).is_dir())
        self.assertIn("smoke: cleanup failed", result.stderr)

    def test_failed_recovery_inventory_retains_workspace(self):
        cases = [
            {"SBX_TEST_SCENARIO": "create-fails-inventory-error"},
            *({"SBX_TEST_SCENARIO": "create-fails-inventory-malformed", "SBX_TEST_INVENTORY": inventory}
              for inventory in ('not-json', '{"sandboxes": []}', '[{}]')),
        ]
        for env in cases:
            with self.subTest(env=env):
                self.log.unlink(missing_ok=True)
                self.state.write_text(json.dumps({"exists": False, "running": False, "generation": 0}))
                result = self.run_smoke(**env)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual([call[:2] for call in self.calls()], [
                    ["ls", "--json"], ["env", "run"], ["env", "rm"], ["ls", "--json"],
                ])
                self.assertTrue(Path(json.loads(self.state.read_text())["workspace"]).is_dir())
                self.assertIn("smoke: cleanup failed", result.stderr)

    def test_occupied_name_never_removes_existing_sandbox(self):
        result = self.run_smoke(SBX_TEST_SCENARIO="occupied")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("AssertionError: smoke name occupied", result.stderr)
        self.assertEqual(self.calls(), [["ls", "--json"]])

    def test_retained_name_after_removal_is_not_recreated_or_removed_again(self):
        result = self.run_smoke(SBX_TEST_SCENARIO="retained")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("AssertionError: removed sandbox still present", result.stderr)
        self.assertEqual([call[:2] for call in self.calls()], [
            ["ls", "--json"], ["env", "run"], ["exec", "-i"],
            ["stop", NAME], ["env", "run"], ["exec", "-i"],
            ["env", "rm"], ["ls", "--json"],
        ])
        state = json.loads(self.state.read_text())
        self.assertTrue(state["exists"])
        self.assertTrue(Path(state["workspace"]).is_dir())

    def test_failed_post_removal_inventory_retains_workspace_without_retrying_removal(self):
        cases = [
            {"SBX_TEST_SCENARIO": "post-remove-inventory-error"},
            *({"SBX_TEST_SCENARIO": "post-remove-inventory-malformed", "SBX_TEST_INVENTORY": inventory}
              for inventory in ('not-json', '{"sandboxes": []}', '[{}]')),
        ]
        for env in cases:
            with self.subTest(env=env):
                self.log.unlink(missing_ok=True)
                self.state.write_text(json.dumps({"exists": False, "running": False, "generation": 0}))
                result = self.run_smoke(**env)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                state = json.loads(self.state.read_text())
                self.assertFalse(state["exists"])
                self.assertTrue(Path(state["workspace"]).is_dir())
                self.assertEqual([call[:2] for call in self.calls()], [
                    ["ls", "--json"], ["env", "run"], ["exec", "-i"],
                    ["stop", NAME], ["env", "run"], ["exec", "-i"],
                    ["env", "rm"], ["ls", "--json"],
                ])


if __name__ == "__main__":
    unittest.main()

"""Exercise the real launcher and Git; replace only the external SBX boundary."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sbx behavior ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "A_Project+One"
        self.repo.mkdir()
        self.git("init", "-q")
        (self.repo / ".gitignore").write_text(".worktrees/\n")
        self.home = self.base / "home"
        self.home.mkdir()
        self.tools = self.base / "tools"
        self.tools.mkdir()
        self.log = self.base / "sbx.jsonl"
        stub = self.tools / "sbx"
        stub.write_text("#!/usr/bin/env python3\n" + '''import json, os, sys
args = sys.argv[1:]
stage = " ".join(args[:2]) if args[:1] == ["env"] else " ".join(args[:1])
if stage == os.environ.get("SBX_TEST_WAIT_STAGE"):
    from pathlib import Path
    import signal, time
    def stopped(number, frame):
        time.sleep(0.1)
        for name, value in json.loads(os.environ.get("SBX_TEST_SIGNAL_MUTATIONS", "[]")):
            target = Path(name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(value)
        Path(os.environ["SBX_TEST_SIGNAL_LOG"]).write_text(str(number))
        sys.exit(int(os.environ.get("SBX_TEST_SIGNAL_EXIT", str(128 + number))))
    if not os.environ.get("SBX_TEST_DEFAULT_SIGNALS"):
        signal.signal(signal.SIGINT, stopped)
        signal.signal(signal.SIGTERM, stopped)
    Path(os.environ["SBX_TEST_READY"]).write_text(str(os.getpid()))
    while True:
        signal.pause()
if stage == os.environ.get("SBX_TEST_MUTATION_STAGE"):
    from pathlib import Path
    import signal
    if os.environ.get("SBX_TEST_REPLACE_METADATA"):
        import shutil
        metadata = Path(os.environ["SBX_TEST_REPLACE_METADATA"])
        saved = metadata.with_name("saved-metadata")
        metadata.rename(saved)
        shutil.copytree(saved, metadata)
    for name, value in json.loads(os.environ.get("SBX_TEST_MUTATIONS", "[]")):
        target = Path(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)
    if os.environ.get("SBX_TEST_SIGNAL"):
        os.kill(os.getppid(), getattr(signal, os.environ["SBX_TEST_SIGNAL"]))
with open(os.environ["SBX_TEST_LOG"], "a") as stream:
    stream.write(json.dumps({"argv": args, "builder": os.environ.get("SBX_KIT_BUILDER")}) + "\\n")
if args == ["version", "--json"]:
    print(os.environ.get("SBX_TEST_VERSION", json.dumps({
        "client": {"version": "v0.50.0", "revision": "testhash"},
        "server": {"state": "unavailable", "error": "sandbox daemon not running"},
    })))
elif args[:2] == ["env", "run"]:
    sys.exit(int(os.environ.get("SBX_TEST_ENV_EXIT", "0")))
elif args[:3] == ["secret", "ls", "--sandbox"]:
    entries = json.loads(os.environ.get("SBX_TEST_CUSTOM_SECRETS", json.dumps([{
        "scope": args[3], "env": "ANTHROPIC_AUTH_TOKEN", "kind": "command",
        "targets": ["aiplatform.eu.rep.googleapis.com", "europe-west1-aiplatform.googleapis.com", "us-east5-aiplatform.googleapis.com"],
        "placeholder": "sbx-cs-vertex-test",
    }])))
    print(json.dumps({"custom_secrets": entries}))
elif args[:3] == ["secret", "ls", "--global"]:
    print('{"custom_secrets": [{"env": "JUNIE_API_KEY", "targets": ["junie.jetbrains.com", "ingrazzio-cloud-prod.labs.jb.gg"], "placeholder": "sbx-cs-test"}]}')
elif args[:2] == ["env", "exec"]:
    sys.exit(int(os.environ.get("SBX_TEST_RUN_EXIT", "0")))
elif args[:1] == ["run"]:
    if os.environ.get("SBX_TEST_STDIN_LOG"):
        from pathlib import Path
        Path(os.environ["SBX_TEST_STDIN_LOG"]).write_text(sys.stdin.read())
    sys.exit(int(os.environ.get("SBX_TEST_RUN_EXIT", "0")))
elif args[:1] == ["stop"]:
    pass
elif args[:1] != ["run"]:
    sys.exit("unexpected SBX command: " + repr(args))
''')
        stub.chmod(0o755)
        self.environ = dict(os.environ)
        for key in ("SBX_PROFILE", "XDG_CONFIG_HOME", "SBX_KIT_BUILDER", "JUNIE_API_KEY", "ANTHROPIC_VERTEX_PROJECT_ID", "CLOUD_ML_REGION"):
            self.environ.pop(key, None)
        self.environ.update(HOME=str(self.home), PATH=str(self.tools) + os.pathsep + os.environ["PATH"],
                            SBX_TEST_LOG=str(self.log), SBX_GIT_AUDIT="strict")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", "-C", str(cwd or self.repo), *args], check=True, text=True, capture_output=True)

    def launch(self, agent="codex", args=(), env=None, cwd=None, launcher=None):
        values = self.environ | (env or {})
        argv = [str(launcher or ROOT / "bin/sbx-dev")]
        if launcher is None:
            argv.append(agent)
        return subprocess.run(argv + list(args), cwd=cwd or self.repo, env=values, text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def operation(self, command):
        return next(call for call in self.calls() if call["argv"][:len(command)] == command)

    def reset_log(self):
        self.log.unlink(missing_ok=True)

    def assert_no_launch(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(call["argv"][:2] == ["env", "run"] or call["argv"][:1] == ["run"] for call in self.calls()))

    def test_supported_version_floor_and_newer_releases(self):
        for version in ("v0.50.0", "v0.50.1", "v0.51.0", "v1.0.0", "v0.50.0+build.5"):
            with self.subTest(version=version):
                self.reset_log()
                result = self.launch(env={"SBX_TEST_VERSION": json.dumps({
                    "client": {"version": version, "revision": "testhash", "build_tags": "cloud"},
                    "server": {"state": "unavailable", "error": "sandbox daemon not running"},
                })})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.calls()[0]["argv"], ["version", "--json"])

    def test_old_malformed_and_floor_prerelease_versions_are_rejected(self):
        for version in ("v0.48.0", "v0.49.1", "v0.49.2", "v0.49.9", "v0.50.0-rc.1", "v0.50", "v0.050.0", ""):
            with self.subTest(version=version):
                self.reset_log()
                self.assert_no_launch(self.launch(env={"SBX_TEST_VERSION": json.dumps({
                    "client": {"version": version, "revision": "testhash", "build_tags": "cloud"},
                    "server": {"state": "unavailable", "error": "sandbox daemon not running"},
                })}))

    def test_malformed_version_inventory_is_rejected(self):
        for inventory in ('junk v0.99.0', '', '[]', '{}', '{"client": null}', '{"client": {}}', '{"client": {"version": 48}}'):
            with self.subTest(inventory=inventory):
                self.reset_log()
                self.assert_no_launch(self.launch(env={"SBX_TEST_VERSION": inventory}))

    def test_environment_provisioning_detaches_with_interactive_approval(self):
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = self.operation(["env", "run"])["argv"]
        self.assertIn("--detach", argv)
        self.assertNotIn("--detached", argv)
        self.assertNotIn("--force", argv)
        self.assertNotIn("--auto-approve", argv)

    def test_personal_and_client_agent_matrix(self):
        for profile, supported in (("personal", {"claude", "codex", "opencode", "antigravity", "junie"}), ("client", {"claude", "copilot"})):
            for agent in ("claude", "codex", "opencode", "antigravity", "junie", "copilot"):
                with self.subTest(profile=profile, agent=agent):
                    self.reset_log()
                    result = self.launch(agent, env={"SBX_PROFILE": profile, "ANTHROPIC_VERTEX_PROJECT_ID": "test-project", "CLOUD_ML_REGION": "us-east5"})
                    if agent in supported:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(self.operation(["env", "run"])["argv"][2], str(ROOT / f"env/{profile}/{agent}.sbxenv.yaml"))
                    else:
                        self.assert_no_launch(result)

    def test_name_is_valid_deterministic_and_same_on_attach(self):
        self.assertEqual(self.launch().returncode, 0)
        argv = self.operation(["env", "run"])["argv"]
        name = argv[argv.index("--name") + 1]
        self.assertRegex(name, r"^codex-a-project-one-[0-9a-f]{8}$")
        self.assertEqual(self.operation(["run"])["argv"], ["run", "--name", name])
        self.reset_log()
        self.assertEqual(self.launch().returncode, 0)
        self.assertIn(name, self.operation(["env", "run"])["argv"])

    def test_empty_slug_has_a_valid_fallback(self):
        other = self.base / "☃ +"
        other.mkdir()
        self.git("init", "-q", cwd=other)
        (other / ".gitignore").write_text(".worktrees/\n")
        result = self.launch(cwd=other)
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = self.operation(["env", "run"])["argv"]
        self.assertRegex(argv[argv.index("--name") + 1], r"^codex-project-[0-9a-f]{8}$")

    def test_same_basename_in_different_paths_has_distinct_names(self):
        self.assertEqual(self.launch().returncode, 0)
        first = self.operation(["env", "run"])["argv"]
        other = self.base / "nested" / self.repo.name
        other.mkdir(parents=True)
        self.git("init", "-q", cwd=other)
        (other / ".gitignore").write_text(".worktrees/\n")
        self.reset_log()
        self.assertEqual(self.launch(cwd=other).returncode, 0)
        second = self.operation(["env", "run"])["argv"]
        self.assertNotEqual(first[first.index("--name") + 1], second[second.index("--name") + 1])

    def test_subdirectory_launch_mounts_repository_root(self):
        nested = self.repo / "sub directory"
        nested.mkdir()
        self.assertEqual(self.launch(cwd=nested).returncode, 0)
        self.assertIn("workspace=" + str(self.repo), self.operation(["env", "run"])["argv"])

    def test_unignored_worktrees_fail_without_creating_directory(self):
        (self.repo / ".gitignore").write_text("")
        self.assert_no_launch(self.launch())
        self.assertFalse((self.repo / ".worktrees").exists())

    def test_tracked_worktrees_cannot_be_hidden_by_ignore_rule(self):
        worktrees = self.repo / ".worktrees"
        worktrees.mkdir()
        (worktrees / "tracked").write_text("tracked content")
        self.git("add", "-f", ".worktrees/tracked")
        self.assert_no_launch(self.launch())

    def test_worktrees_symlink_cannot_escape_workspace(self):
        outside = self.base / "outside"
        outside.mkdir()
        (self.repo / ".worktrees").symlink_to(outside, target_is_directory=True)
        self.assert_no_launch(self.launch())

    def test_linked_worktree_with_git_metadata_outside_mount_is_rejected(self):
        self.git("add", ".gitignore")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
        linked = self.repo / ".worktrees/topic"
        self.git("worktree", "add", "-qb", "topic", str(linked))
        self.assert_no_launch(self.launch(cwd=linked))
        self.assertIn("worktree", self.launch(cwd=linked).stderr.lower())

    def test_symlinked_public_launcher_in_path_with_spaces(self):
        links = self.base / "links with spaces"
        links.mkdir()
        (links / "launcher").symlink_to(ROOT / "bin/sbx-dev")
        wrapper = links / "codex-sbx"
        wrapper.symlink_to("launcher")
        result = self.launch(launcher=wrapper)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.operation(["env", "run"])["argv"][2], str(ROOT / "env/personal/codex.sbxenv.yaml"))

    def test_agent_argv_preserves_empty_strings_and_literal_shell_syntax(self):
        marker = self.base / "must not exist"
        args = ["", "space in argument", "$(touch '" + str(marker) + "')", "`echo command`", "; echo shell", "--", "--name=literal"]
        result = self.launch(args=args)
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = self.operation(["run"])["argv"]
        self.assertEqual(argv[argv.index("--") + 1:], args)
        self.assertFalse(marker.exists())

    def test_environment_failure_never_attaches(self):
        result = self.launch(env={"SBX_TEST_ENV_EXIT": "17"})
        self.assertEqual(result.returncode, 17)
        self.assertFalse(any(call["argv"][:1] == ["run"] for call in self.calls()))

    def test_profile_file_and_overlay_follow_home(self):
        config = self.home / ".config/docker-sandboxes"
        config.mkdir(parents=True)
        (config / "profile").write_text(" client\n")
        overlay = config / "client.sbxenv.yaml"
        overlay.write_text("schemaVersion: '1'\n")
        result = self.launch("copilot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(overlay), self.operation(["env", "run"])["argv"])

    def test_xdg_config_home_and_environment_profile_precedence(self):
        config_root = self.base / "xdg config"
        config = config_root / "docker-sandboxes"
        config.mkdir(parents=True)
        (config / "profile").write_text("client\n")
        result = self.launch("copilot", env={"XDG_CONFIG_HOME": str(config_root)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.reset_log()
        result = self.launch(env={"XDG_CONFIG_HOME": str(config_root), "SBX_PROFILE": "personal"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(ROOT / "env/personal/codex.sbxenv.yaml"), self.operation(["env", "run"])["argv"])

    def test_client_claude_requires_both_vertex_arguments(self):
        self.assert_no_launch(self.launch("claude", env={"SBX_PROFILE": "client"}))
        self.reset_log()
        self.assert_no_launch(self.launch("claude", env={"SBX_PROFILE": "client", "ANTHROPIC_VERTEX_PROJECT_ID": "project"}))

    def test_client_claude_executes_with_current_environment_and_preserves_argv(self):
        config = self.home / ".config/docker-sandboxes"
        config.mkdir(parents=True)
        overlay = config / "client.sbxenv.yaml"
        overlay.write_text('schemaVersion: "1"\nenv:\n  VERTEX_REGION_CLAUDE_HAIKU_4_5: europe-west1\n')
        env = {"SBX_PROFILE": "client", "ANTHROPIC_VERTEX_PROJECT_ID": "test-project", "CLOUD_ML_REGION": "eu"}
        for args in ([], ["--model", "haiku", "", "space in argument", "$(echo literal)", "--"]):
            with self.subTest(args=args):
                self.reset_log()
                result = self.launch("claude", args=args, env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = [call["argv"] for call in self.calls() if call["argv"][:2] == ["env", "exec"]]
                self.assertEqual(len(calls), 1, "Client Claude must apply the current native environment")
                provision = self.operation(["env", "run"])["argv"]
                name = provision[provision.index("--name") + 1]
                self.assertEqual(calls[0], [
                    "env", "exec", "--name", name,
                    "--env-arg", "workspace=" + str(self.repo),
                    "--env-arg", "vertexProject=test-project",
                    "--env-arg", "vertexRegion=eu",
                    "--env", "ANTHROPIC_AUTH_TOKEN=sbx-cs-vertex-test",
                    str(ROOT / "env/client/claude.sbxenv.yaml"),
                    str(ROOT / "env/common.sbxenv.yaml"), str(overlay),
                    "--", "claude", "--dangerously-skip-permissions", *args,
                ])
                self.assertFalse(any(call["argv"][:1] == ["run"] for call in self.calls()))

    def test_client_claude_missing_scoped_secret_never_executes(self):
        result = self.launch("claude", env={
            "SBX_PROFILE": "client", "ANTHROPIC_VERTEX_PROJECT_ID": "test-project",
            "CLOUD_ML_REGION": "eu", "SBX_TEST_CUSTOM_SECRETS": "[]",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Vertex", result.stderr)
        self.assertFalse(any(call["argv"][:2] == ["env", "exec"] for call in self.calls()))
        self.assertFalse(any(call["argv"][:3] == ["secret", "ls", "--global"] for call in self.calls()))

    def test_vertex_placeholder_is_not_used_for_personal_claude_or_client_copilot(self):
        for agent, profile in (("claude", "personal"), ("copilot", "client")):
            with self.subTest(agent=agent, profile=profile):
                self.reset_log()
                result = self.launch(agent, env={"SBX_PROFILE": profile})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(any(call["argv"][:2] == ["secret", "ls"] for call in self.calls()))
                self.assertNotIn("ANTHROPIC_AUTH_TOKEN", self.log.read_text())

    def test_client_claude_environment_failure_never_executes(self):
        result = self.launch("claude", env={
            "SBX_PROFILE": "client", "ANTHROPIC_VERTEX_PROJECT_ID": "test-project",
            "CLOUD_ML_REGION": "eu", "SBX_TEST_ENV_EXIT": "17",
        })
        self.assertEqual(result.returncode, 17)
        self.assertFalse(any(call["argv"][:2] == ["env", "exec"] or call["argv"][:1] == ["run"]
                             for call in self.calls()))

    def test_junie_uses_native_secret_instead_of_forwarding_host_key(self):
        result = self.launch("junie", env={"JUNIE_API_KEY": "secret-value"})
        self.assertEqual(result.returncode, 0, result.stderr)
        argv = self.operation(["env", "exec"])["argv"]
        self.assertEqual(argv[argv.index("--env") + 1], "JUNIE_API_KEY=sbx-cs-test")
        self.assertEqual(argv[-3:], ["--", "junie", "--brave"])
        self.assertNotIn("secret-value", self.log.read_text())
        self.reset_log()
        self.assertEqual(self.launch("junie").returncode, 0)
        self.assertIn("JUNIE_API_KEY=sbx-cs-test", self.operation(["env", "exec"])["argv"])

    def test_sandbox_builder_default_and_explicit_override(self):
        self.assertEqual(self.launch().returncode, 0)
        self.assertEqual(self.operation(["env", "run"])["builder"], "sandbox")
        self.reset_log()
        self.assertEqual(self.launch(env={"SBX_KIT_BUILDER": "host"}).returncode, 0)
        self.assertEqual(self.operation(["env", "run"])["builder"], "host")

    def test_outside_git_repository_fails_before_launch(self):
        self.assert_no_launch(self.launch(cwd=self.home))

    def test_command_config_is_rejected_before_host_git_can_execute_it(self):
        marker = self.base / "host-command-ran"
        self.git("config", "core.fsmonitor", f"touch '{marker}'")
        result = self.launch()
        self.assert_no_launch(result)
        self.assertIn("core.fsmonitor", result.stderr)
        self.assertFalse(marker.exists(), "audit must precede ls-files/check-ignore")

    def test_executable_config_families_are_rejected(self):
        config = self.repo / ".git/config"
        original = config.read_bytes()
        keys = ("core.hooksPath", "core.sshCommand", "core.pager", "core.editor",
                "filter.lfs.process", "diff.custom.textconv", "diff.external",
                "merge.custom.driver", "alias.run", "credential.helper",
                "credential.https://example.invalid.helper", "gpg.ssh.program",
                "hook.configured.command", "trailer.custom.cmd", "protocol.allow", "protocol.ext.allow",
                "submodule.sub.update", "sendemail.tocmd", "sendemail.work.cccmd", "browser.custom.cmd", "man.custom.cmd",
                "remote.origin.vcs",
                "trailer.custom.cmd", "trailer.custom.command",
                "core.alternateRefsCommand", "gc.recentObjectsHook", "interactive.diffFilter",
                "difftool.custom.cmd", "mergetool.custom.cmd", "gpg.ssh.defaultKeyCommand",
                "tar.custom.command", "difftool.custom.path", "mergetool.custom.path")
        for key in keys:
            with self.subTest(key=key):
                config.write_bytes(original)
                self.reset_log()
                self.git("config", key, "!touch /never-execute")
                result = self.launch()
                self.assert_no_launch(result)
                self.assertIn(key.lower(), result.stderr.lower())

    def test_benign_local_settings_and_non_shell_alias_remain_usable(self):
        self.git("config", "user.name", "Test Developer")
        self.git("config", "alias.st", "status --short")
        self.assertEqual(self.launch().returncode, 0)

    def test_default_policy_accepts_repository_integrations_without_running_them(self):
        self.environ.pop("SBX_GIT_AUDIT")
        marker = self.base / "host-command-ran"
        self.git("config", "core.hooksPath", str(self.base / "old-checkout/.git/hooks"))
        self.git("config", "core.fsmonitor", f"touch '{marker}'")
        self.git("config", "filter.lfs.process", "git-lfs filter-process")
        hooks = self.repo / ".git/hooks"
        hooks.mkdir(exist_ok=True)
        (hooks / "pre-commit").write_text(f"#!/bin/sh\ntouch '{marker}'\n")
        (hooks / "pre-commit").chmod(0o755)
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.repo / ".git").is_dir())
        self.assertFalse(marker.exists())

    def test_compatible_postflight_accepts_repository_integration_changes(self):
        hook = self.repo / ".git/hooks/pre-commit"
        result = self.launch(env={"SBX_GIT_AUDIT": "compatible",
                                  "SBX_TEST_MUTATION_STAGE": "run",
                                  "SBX_TEST_MUTATIONS": json.dumps([[str(hook), "new project hook"]])})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(hook.exists())
        self.assertFalse(any(call["argv"][:1] == ["stop"] for call in self.calls()))

    def test_invalid_git_audit_policy_fails_before_launch(self):
        result = self.launch(env={"SBX_GIT_AUDIT": "typo"})
        self.assert_no_launch(result)
        self.assertIn("SBX_GIT_AUDIT", result.stderr)

    def test_non_shell_alias_cannot_inject_command_configuration(self):
        for alias in ('-c core.fsmonitor=attack status', '"-c" core.fsmonitor=attack status',
                      '--config-env=core.fsmonitor=ATTACK status'):
            with self.subTest(alias=alias):
                self.git("config", "alias.indirect", alias)
                self.reset_log()
                result = self.launch()
                self.assert_no_launch(result)
                self.assertIn("alias.indirect", result.stderr)

    def test_includes_and_malformed_config_fail_closed(self):
        config = self.repo / ".git/config"
        original = config.read_bytes()
        for suffix in ('\n[include]\n path = ../hidden-config\n',
                       '\n[includeIf "onbranch:inactive"]\n path = ../hidden-config\n',
                       '\n[broken\n'):
            with self.subTest(suffix=suffix):
                config.write_bytes(original + suffix.encode())
                self.reset_log()
                self.assert_no_launch(self.launch())

    def test_non_sample_hooks_and_metadata_symlinks_are_rejected(self):
        hooks = self.repo / ".git/hooks"
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 0\n")
        self.assert_no_launch(self.launch())
        hook.unlink()
        target = self.base / "host-config"
        config = self.repo / ".git/config"
        config.rename(target)
        config.symlink_to(target)
        self.reset_log()
        self.assert_no_launch(self.launch())

    def test_worktree_and_submodule_configs_are_audited_even_when_inactive(self):
        for relative in ("config.worktree", "worktrees/topic/config.worktree", "modules/sub/config",
                         "worktrees/objects/config.worktree", "modules/objects/config"):
            with self.subTest(relative=relative):
                path = self.repo / ".git" / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('[core]\n fsmonitor = malicious-command\n')
                self.reset_log()
                result = self.launch()
                self.assert_no_launch(result)
                self.assertIn("core.fsmonitor", result.stderr)
                path.unlink()

    def test_metadata_mutations_are_detected_after_all_session_branches(self):
        for agent, profile, stage in (("codex", "personal", "run"),
                                      ("junie", "personal", "env exec"),
                                      ("claude", "client", "env exec"),
                                      ("codex", "personal", "env run")):
            with self.subTest(agent=agent, profile=profile, stage=stage):
                target = self.repo / ".git/config.worktree"
                self.reset_log()
                result = self.launch(agent, env={
                    "SBX_PROFILE": profile, "ANTHROPIC_VERTEX_PROJECT_ID": "project",
                    "CLOUD_ML_REGION": "eu", "SBX_TEST_MUTATION_STAGE": stage,
                    "SBX_TEST_MUTATIONS": json.dumps([[str(target), '[core]\n fsmonitor = attack\n']]),
                })
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn("core.fsmonitor", result.stderr)
                self.restore_quarantine()
                target.unlink()

    def test_post_audit_runs_on_failure_and_preserves_child_exit_status(self):
        target = self.repo / ".git/hooks/pre-commit"
        result = self.launch(env={"SBX_TEST_RUN_EXIT": "17", "SBX_TEST_MUTATION_STAGE": "run",
                                  "SBX_TEST_MUTATIONS": json.dumps([[str(target), "attack"]])})
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertIn("pre-commit", result.stderr)

    def signal_launcher(self, number, stage, extra=None):
        ready, received = self.base / "ready", self.base / "received-signal"
        ready.unlink(missing_ok=True)
        received.unlink(missing_ok=True)
        env = self.environ | {"SBX_TEST_WAIT_STAGE": stage, "SBX_TEST_READY": str(ready),
                              "SBX_TEST_SIGNAL_LOG": str(received)} | (extra or {})
        process = subprocess.Popen([str(ROOT / "bin/sbx-dev"), "codex"], cwd=self.repo,
                                   env=env, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "SBX child did not become ready")
            os.kill(process.pid, number)
            stdout, stderr = process.communicate(timeout=3)
            if not env.get("SBX_TEST_DEFAULT_SIGNALS"):
                self.assertEqual(received.read_text(), str(number), "launcher must forward the signal")
            return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate()

    def test_launcher_forwards_signals_and_audits_after_child_finishes(self):
        target = self.repo / ".git/hooks/pre-commit"
        for stage in ("env run", "run"):
            for number in (signal.SIGINT, signal.SIGTERM):
                with self.subTest(stage=stage, signal=number):
                    result = self.signal_launcher(number, stage, {
                        "SBX_TEST_SIGNAL_MUTATIONS": json.dumps([[str(target), "attack"]])})
                    self.assertEqual(result.returncode, 128 + number, result.stderr)
                    self.assertIn("pre-commit", result.stderr)
                    self.assertFalse((self.repo / ".git").exists())
                    self.assertEqual([call["argv"][0] for call in self.calls()].count("stop"), 1)
                    self.restore_quarantine()
                    target.unlink()
                    self.reset_log()

    def test_background_sbx_does_not_inherit_ignored_interrupt(self):
        result = self.signal_launcher(signal.SIGINT, "run", {"SBX_TEST_DEFAULT_SIGNALS": "1"})
        self.assertEqual(result.returncode, 130, result.stderr)

    def test_sbx_child_keeps_launcher_stdin(self):
        received = self.base / "stdin"
        result = subprocess.run([str(ROOT / "bin/sbx-dev"), "codex"], cwd=self.repo,
                                env=self.environ | {"SBX_TEST_STDIN_LOG": str(received)},
                                input="interactive input\n", text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(received.read_text(), "interactive input\n")

    def test_preflight_audits_metadata_only_once(self):
        audit_log = self.base / "audits"
        python = self.tools / "python3"
        python.write_text(f"#!{sys.executable}\n" + '''import os, sys
if sys.argv[1:2] and sys.argv[1].endswith("/audit-git.py"):
    with open(os.environ["SBX_TEST_AUDIT_LOG"], "a") as stream:
        stream.write(repr(sys.argv[2:]) + "\\n")
os.execv(sys.executable, [sys.executable, *sys.argv[1:]])
''')
        python.chmod(0o755)
        result = self.launch(env={"SBX_TEST_AUDIT_LOG": str(audit_log)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(audit_log.read_text().splitlines()), 2,
                         "one preflight audit and one postflight audit")

    def test_post_audit_rejects_replacement_git_directory(self):
        result = self.launch(env={"SBX_TEST_MUTATION_STAGE": "run",
                                  "SBX_TEST_REPLACE_METADATA": str(self.repo / ".git")})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("replaced", result.stderr)

    def test_git_metadata_routing_cannot_hide_another_common_directory(self):
        hidden = self.repo / "hidden-metadata"
        hidden.mkdir()
        (self.repo / ".git/commondir").write_text(str(hidden))
        self.assert_no_launch(self.launch())

    def test_submodule_commondir_cannot_hide_config_in_object_store(self):
        hidden = self.repo / ".git/objects/hidden-common"
        hidden.mkdir(parents=True)
        (hidden / "config").write_text('[core]\n fsmonitor = attack\n')
        module = self.repo / ".git/modules/sub"
        module.mkdir(parents=True)
        (module / "commondir").write_text(str(hidden))
        self.assert_no_launch(self.launch())

    def test_remote_helper_urls_are_rejected(self):
        config = self.repo / ".git/config"
        original = config.read_bytes()
        for key, value in (("remote.origin.url", "ext::sh -c 'touch /never-execute'"),
                           ("remote.origin.pushurl", "fd::3"),
                           ("url.ext::sh -c x.insteadOf", "https://example.invalid/"),
                           ("url.https://example.invalid/.insteadOf", "ext::sh -c x")):
            with self.subTest(key=key):
                config.write_bytes(original)
                self.reset_log()
                self.git("config", key, value)
                self.assert_no_launch(self.launch())
        config.write_bytes(original)
        self.git("config", "remote.origin.url", "https://example.invalid/repo.git")
        self.git("config", "url.https://example.invalid/.insteadOf", "example:")
        self.reset_log()
        self.assertEqual(self.launch().returncode, 0)

    def restore_quarantine(self):
        (quarantined,) = self.repo.glob(".git.sbx-quarantine-*")
        quarantined.rename(self.repo / ".git")

    def commit_all(self):
        self.git("add", ".gitignore")
        self.git("-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "init")

    def test_genuine_linked_worktree_is_accepted(self):
        self.commit_all()
        self.git("worktree", "add", "-q", ".worktrees/topic", "-b", "topic")
        self.git("worktree", "add", "-q", ".worktrees/group/nested", "-b", "nested")
        self.assertEqual(self.launch().returncode, 0)

    def test_nested_repository_is_accepted_and_audited(self):
        nested = self.repo / ".worktrees/group/arbitrary repo"
        subprocess.run(["git", "init", "-q", "--template=", str(nested)], check=True)
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        (nested / ".git/config").write_text("[core]\nfsmonitor = attack\n")
        self.reset_log()
        result = self.launch()
        self.assert_no_launch(result)
        self.assertIn("core.fsmonitor", result.stderr)

    def test_redirected_worktrees_bare_repositories_and_symlinks_are_rejected(self):
        worktrees = self.repo / ".worktrees"
        worktrees.mkdir()
        crafted = self.repo / "crafted"
        crafted.mkdir()
        topic = worktrees / "topic"
        topic.mkdir()
        (topic / ".git").write_text(f"gitdir: {crafted}\n")
        self.reset_log()
        self.assert_no_launch(self.launch())
        shutil.rmtree(topic)
        bare = worktrees / "bare"
        subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
        self.reset_log()
        self.assert_no_launch(self.launch())
        shutil.rmtree(bare)
        (worktrees / "link").symlink_to(self.base)
        self.reset_log()
        self.assert_no_launch(self.launch())

    def test_nested_repository_postflight_failure_quarantines_its_metadata(self):
        nested = self.repo / ".worktrees/group/arbitrary repo"
        subprocess.run(["git", "init", "-q", "--template=", str(nested)], check=True)
        hook = nested / ".git/hooks/pre-commit"
        result = self.launch(env={"SBX_TEST_MUTATION_STAGE": "run",
                                  "SBX_TEST_MUTATIONS": json.dumps([[str(hook), "attack"]])})
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.repo / ".git").exists())
        self.assertFalse((nested / ".git").exists())
        (saved,) = nested.glob(".git.sbx-quarantine-*")
        self.assertEqual((saved / "hooks/pre-commit").read_text(), "attack")
        self.assertIn(str(saved), result.stderr)
        self.assertEqual([call["argv"][0] for call in self.calls()].count("stop"), 1)

    def test_failed_post_audit_stops_sandbox_and_quarantines_git_metadata(self):
        target = self.repo / ".git/hooks/pre-commit"
        result = self.launch(env={"SBX_TEST_MUTATION_STAGE": "run",
                                  "SBX_TEST_MUTATIONS": json.dumps([[str(target), "attack"]])})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.repo / ".git").exists())
        quarantined = list(self.repo.glob(".git.sbx-quarantine-*"))
        self.assertEqual(len(quarantined), 1, result.stderr)
        self.assertTrue((quarantined[0] / "hooks/pre-commit").exists())
        self.assertIn(str(quarantined[0]), result.stderr)
        self.assertEqual([call["argv"][0] for call in self.calls()].count("stop"), 1)
        self.reset_log()
        self.assert_no_launch(self.launch())

    def test_preflight_failure_never_quarantines(self):
        self.git("config", "core.fsmonitor", "attack")
        self.assert_no_launch(self.launch())
        self.assertTrue((self.repo / ".git").is_dir())
        self.assertEqual(list(self.repo.glob(".git.sbx-quarantine-*")), [])

    def test_agent_interrupt_does_not_override_agent_exit_status(self):
        # Model an agent that handles Ctrl-C successfully, with its handler ready
        # before signaling the launcher so forwarding cannot race child startup.
        result = self.signal_launcher(signal.SIGINT, "run", {"SBX_TEST_SIGNAL_EXIT": "0"})
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()

# AGENTS.md

Docker Sandboxes harnesses for Claude Code, Codex, OpenCode, and Antigravity
CLI on macOS. This is infrastructure/tooling, not an application: it builds
four sandbox template images and launches one deterministic sandbox per target
repository and agent.

## Architecture

The shared toolchain lives in `shared/`. Each harness owns its agent-specific
files under `harnesses/<name>/`:

1. `Dockerfile` builds `claude-sbx:local`, `codex-sbx:local`,
   `opencode-sbx:local`, or `antigravity-sbx:local`. It contains the toolchain
   only; no agent configuration or credentials.
2. `kit/spec.yaml` defines the network-egress allowlist and agent instructions.
   The kit is applied only when a sandbox is created.
3. `bin/` launches or reuses the harness sandbox.
4. `scripts/bootstrap.sh` installs or registers agent-specific integrations
   after creation; `scripts/verify.sh` verifies the resulting sandbox.

Root commands in `bin/` are thin delegates:

- `claude-sbx` → `harnesses/claude-code/bin/claude-code-sbx`
- `codex-sbx` → `harnesses/codex/bin/codex-sbx`
- `opencode-sbx` → `harnesses/opencode/bin/opencode-sbx`
- `antigravity-sbx` → `harnesses/antigravity-cli/bin/antigravity-sbx`

Do not bake Claude plugins, Codex/OpenCode/Antigravity MCP configuration,
credentials, or session state into any image. Docker Sandboxes recreates
agent-managed configuration when a sandbox is created. Claude plugins belong
in the Claude bootstrap; Codex, OpenCode, and Antigravity MCP registration,
Superpowers, Caveman, and Playwright skills belong in their respective
bootstraps.

Mount model: the target repository is mounted read/write at the same absolute
path inside its sandbox. When it differs from this repository, this harness
repository is mounted read-only so bootstrap and verification scripts remain
available.

## Commands

- `make test` — runs all host-side Bash tests in `tests/`.
- `bash tests/test_name.sh` — runs one test. Tests may source root wrapper
  functions without launching a sandbox.
- `make rebuild` or `make rebuild-claude` — rebuilds and loads
  `claude-sbx:local`.
- `make rebuild-codex` — rebuilds and loads `codex-sbx:local`.
- `make rebuild-opencode` — rebuilds and loads `opencode-sbx:local`.
- `make rebuild-antigravity` — rebuilds and loads `antigravity-sbx:local`.
- `make verify` — runs the Claude verification script. It is intended to run
  inside a sandbox via `sbx exec`, as described in `docs/usage.md`; it will
  fail on the host because sandbox-only tools are absent.
  `make verify-opencode` and `make verify-antigravity` run the OpenCode and
  Antigravity verification scripts.

## Non-obvious rules

- Keep Node and Go versions synchronized in all harness Dockerfiles and all
  verification scripts. The current pins are Node `24.19.0` and Go `1.26.6`.
- Existing sandboxes retain their old template and kit. After changing a
  Dockerfile, shared toolchain script, or harness kit, rebuild the matching
  template, run `sbx rm <name>`, then relaunch the matching command from the
  target repository.
- Sandbox names are deterministic and distinct:
  `claude-<repo-slug>-<8-hex-path-digest>`,
  `codex-<repo-slug>-<8-hex-path-digest>`,
  `opencode-<repo-slug>-<8-hex-path-digest>`, and
  `antigravity-<repo-slug>-<8-hex-path-digest>`. The launcher function
  `sandbox_name_for_repo` defines the exact scheme used by tests.
- All launchers exit with code `3` when `.worktrees/` is not ignored by Git in
  the target repository. Preserve this intentional guard.
- Network egress is allowlisted per harness in
  `harnesses/<name>/kit/spec.yaml`. If bootstrap fails due to network policy,
  inspect `sbx policy log <sandbox-name>`, add only the required domain, and
  recreate the sandbox.
- OpenJDK 25, Maven, and Gradle are present in all templates and verified by
  all verification scripts.
- All bootstrap scripts must remain idempotent because they are rerun for
  existing sandboxes. Caveman is a Claude plugin and a pinned skill in the
  Codex, OpenCode, and Antigravity bootstraps; do not run its standalone hook
  installer.
- Root wrappers, harness launchers, and bootstrap scripts use `BASH_SOURCE`
  guards so tests can source them without side effects. Preserve that behavior.

## Style

- Use Bash with `set -euo pipefail`; keep shellcheck and shfmt clean.
- Do not commit generated images, caches, credentials, agent session state, or
  machine-specific configuration.
- There is no remote or CI; the primary branch is `main`.

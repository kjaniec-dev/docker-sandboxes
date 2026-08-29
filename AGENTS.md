# AGENTS.md

Docker Sandboxes harnesses for Claude Code and Codex on macOS. This is
infrastructure/tooling, not an application: it builds two sandbox template
images and launches one deterministic sandbox per target repository and agent.

## Architecture

The shared toolchain lives in `shared/`. Each harness owns its agent-specific
files under `harnesses/<name>/`:

1. `Dockerfile` builds either `claude-sbx:local` or `codex-sbx:local`. It
   contains the toolchain only; no agent configuration or credentials.
2. `kit/spec.yaml` defines the network-egress allowlist and agent instructions.
   The kit is applied only when a sandbox is created.
3. `bin/` launches or reuses the harness sandbox.
4. `scripts/bootstrap.sh` installs or registers agent-specific integrations
   after creation; `scripts/verify.sh` verifies the resulting sandbox.

Root commands in `bin/` are thin delegates:

- `claude-sbx` → `harnesses/claude-code/bin/claude-code-sbx`
- `codex-sbx` → `harnesses/codex/bin/codex-sbx`

Do not bake Claude plugins, Codex MCP configuration, credentials, or session
state into either image. Docker Sandboxes recreates agent-managed configuration
when a sandbox is created. Claude plugins belong in the Claude bootstrap;
Codex MCP registration, Superpowers, and Playwright skills belong in the Codex
bootstrap.

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
- `make verify` — runs the Claude verification script. It is intended to run
  inside a sandbox via `sbx exec`, as described in `docs/usage.md`; it will
  fail on the host because sandbox-only tools are absent.

## Non-obvious rules

- Keep Node and Go versions synchronized in both harness Dockerfiles and both
  verification scripts. The current pins are Node `24.19.0` and Go `1.26.6`.
- Existing sandboxes retain their old template and kit. After changing a
  Dockerfile, shared toolchain script, or harness kit, rebuild the matching
  template, run `sbx rm <name>`, then relaunch the matching command from the
  target repository.
- Sandbox names are deterministic and distinct:
  `claude-<repo-slug>-<8-hex-path-digest>` and
  `codex-<repo-slug>-<8-hex-path-digest>`. The launcher function
  `sandbox_name_for_repo` defines the exact scheme used by tests.
- Both launchers exit with code `3` when `.worktrees/` is not ignored by Git in
  the target repository. Preserve this intentional guard.
- Network egress is allowlisted per harness in
  `harnesses/<name>/kit/spec.yaml`. If bootstrap fails due to network policy,
  inspect `sbx policy log <sandbox-name>`, add only the required domain, and
  recreate the sandbox.
- OpenJDK 25, Maven, and Gradle are present in both templates and verified by
  both verification scripts.
- Both bootstrap scripts must remain idempotent because they are rerun for
  existing sandboxes. Caveman is Claude-plugin-only; do not run its standalone
  hook installer as well.
- Root wrappers, harness launchers, and bootstrap scripts use `BASH_SOURCE`
  guards so tests can source them without side effects. Preserve that behavior.

## Style

- Use Bash with `set -euo pipefail`; keep shellcheck and shfmt clean.
- Do not commit generated images, caches, credentials, agent session state, or
  machine-specific configuration.
- There is no remote or CI; the primary branch is `main`.

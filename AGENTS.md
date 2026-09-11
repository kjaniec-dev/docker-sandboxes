# AGENTS.md

Docker Sandboxes harnesses for Claude Code, Codex, OpenCode, Antigravity CLI,
and Junie on macOS. This is infrastructure/tooling, not an application: it
builds five sandbox template images and launches one deterministic sandbox per
target repository and agent.

## Architecture

The shared toolchain and launcher/rebuild lifecycle live in `shared/`.
Each harness owns its agent-specific
files under `harnesses/<name>/`:

1. `Dockerfile` builds `claude-sbx:local`, `codex-sbx:local`,
   `opencode-sbx:local`, `agy-sbx:local`, or `junie-sbx:local`. It contains the toolchain
   only; no agent configuration or credentials.
2. `kit/spec.yaml` is a full sandbox kit defining the agent, network-egress
   allowlist, instructions and synchronous `setup.install` bootstrap.
   The kit is applied only when a sandbox is created.
3. `bin/` launches or reuses the harness sandbox through `sbx create` and `sbx run --name`.
4. `scripts/bootstrap.sh` installs or registers agent-specific integrations
   during creation; `scripts/verify.sh` verifies the resulting sandbox.

Root commands in `bin/` are thin delegates:

- `claude-sbx` → `harnesses/claude-code/bin/claude-code-sbx`
- `codex-sbx` → `harnesses/codex/bin/codex-sbx`
- `opencode-sbx` → `harnesses/opencode/bin/opencode-sbx`
- `agy-sbx` → `harnesses/antigravity-cli/bin/agy-sbx`
- `junie-sbx` → `harnesses/junie/bin/junie-sbx`

Do not bake Claude plugins, Codex/OpenCode/Antigravity/Junie MCP configuration,
credentials, or session state into any image. Docker Sandboxes recreates
agent-managed configuration when a sandbox is created. Claude plugins belong
in the Claude bootstrap; agent MCP registration belongs in each bootstrap.
Superpowers, pinned Caveman and Playwright skills live in the host's native
sbx skills store, managed by `bin/sbx-skills` and `shared/skills.sh`. Bootstraps
link their discovery directories to the explicitly mounted shared store.

Mount model: the target repository is mounted read/write at the same absolute
path inside its sandbox. When it differs from this repository, this harness
repository is mounted read-only so bootstrap and verification scripts remain
available. The shared skills store is also mounted read/write at its original
absolute path, intentionally sharing skill changes across all five agents.

## Commands

- `make test` — runs all host-side Bash tests in `tests/`.
- `bin/sbx-skills [--update]` — ensure/list shared skills; optionally refresh
  Superpowers and Playwright while keeping Caveman pinned.
- `bin/sbx-policy-audit [<sandbox>] [--limit N]` — read-only review of
  `sbx policy log`: reports blocked network requests per sandbox, compares
  them with the matching harness kit allowlist, and prints scoped
  `sbx policy allow` suggestions plus the kit file to update.
- `bin/sbx-new-harness <name> [--prefix <p>] [--base shell|claude-code|codex|opencode]`
  — scaffolds a new harness (Dockerfile, kit, launcher, bootstrap, verify),
  root delegates, and a layout test without overwriting existing files, then
  prints the remaining manual wiring steps.
- `bash tests/test_name.sh` — runs one test. Tests may source root wrapper
  functions without launching a sandbox.
- `make rebuild` or `make rebuild-claude` — rebuilds and loads
  `claude-sbx:local`.
- `make rebuild-codex` — rebuilds and loads `codex-sbx:local`.
- `make rebuild-opencode` — rebuilds and loads `opencode-sbx:local`.
- `make rebuild-agy` — rebuilds and loads `agy-sbx:local`.
- `make rebuild-junie` — rebuilds and loads `junie-sbx:local`.
- `make verify` — runs the Claude verification script. It is intended to run
  inside a sandbox via `sbx exec`, as described in `docs/usage.md`; it will
  fail on the host because sandbox-only tools are absent.
  `make verify-opencode`, `make verify-agy`, and `make verify-junie` run the
  corresponding verification scripts.

## Non-obvious rules

- Keep Node and Go versions synchronized in all harness Dockerfiles and all
  verification scripts. The current pins are Node `24.19.0` and Go `1.26.6`.
- Existing sandboxes retain their old template and kit. After changing a
  Dockerfile or shared toolchain script, rebuild the matching template and
  recreate the sandbox. Kit changes need recreation, not an image rebuild.
  Additive network fixes can be applied immediately with
  `sbx policy allow network --sandbox <name> <domain>`; also update the kit
  for future sandboxes. Launcher changes apply on the next launch.
- Sandbox names are deterministic and distinct:
  `claude-<repo-slug>-<8-hex-path-digest>`,
  `codex-<repo-slug>-<8-hex-path-digest>`,
  `opencode-<repo-slug>-<8-hex-path-digest>`, and
  `agy-<repo-slug>-<8-hex-path-digest>`, and
  `junie-<repo-slug>-<8-hex-path-digest>`. The launcher function
  `sandbox_name_for_repo` defines the exact scheme used by tests.
- All launchers exit with code `3` when `.worktrees/` is not ignored by Git in
  the target repository. Preserve this intentional guard.
- Network egress is allowlisted per harness in
  `harnesses/<name>/kit/spec.yaml`. If bootstrap fails due to network policy,
  inspect `sbx policy log <sandbox-name>`, add only the required domain, and
  apply a sandbox-scoped allow rule as described above.
- OpenJDK 25, Maven, and Gradle are present in all templates and verified by
  all verification scripts.
- Require sbx 0.42.1+ and host jq. Launchers generate no environment files;
  Junie API keys are session-only overrides on `sbx run`.
- All bootstrap scripts must remain idempotent for explicit repair runs.
  Native `setup.install` runs them at creation, not on every attachment.
  Caveman is a Claude plugin and a pinned shared skill; do not run its
  standalone hook installer.
- Root wrappers, harness launchers, and bootstrap scripts use `BASH_SOURCE`
  guards so tests can source them without side effects. Preserve that behavior.

## Style

- Use Bash with `set -euo pipefail`; keep shellcheck and shfmt clean.
- Do not commit generated images, caches, credentials, agent session state, or
  machine-specific configuration.
- There is no remote or CI; the primary branch is `main`.

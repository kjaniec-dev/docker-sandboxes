# Multi-Harness Docker Sandboxes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an independently runnable Codex harness and reorganize the existing Claude Code setup into an extensible multi-harness repository while preserving `claude-sbx` compatibility.

**Architecture:** Each harness owns its agent-specific Dockerfile, kit, wrapper, bootstrap and verification script. Two shared toolchain installer scripts are invoked by both agent-specific Dockerfiles, while root entrypoints delegate to harness implementations. Claude and Codex use distinct template tags, sandbox names and agent configuration.

**Tech Stack:** Bash, Dockerfiles, Docker Desktop Sandboxes (`sbx`), Docker Kits, Claude Code, OpenAI Codex CLI, Node.js 24.19.0, Go 1.26.6, Python/uv, OpenJDK 25, Maven, Gradle, Playwright CLI.

**Spec:** `docs/superpowers/specs/2026-08-26-multi-harness-design.md`

## Global Constraints

- Host target is macOS with Docker Desktop and the `sbx` CLI installed.
- Use Docker Sandboxes direct workspace mode; never pass `--clone`.
- Mount the selected Git repository read/write at its original absolute path.
- Mount this infrastructure repository read-only when it differs from the target repository.
- Use project-local `.worktrees/`, and refuse to start when it is not Git-ignored.
- Claude images extend `docker/sandbox-templates:claude-code-docker`; Codex images extend `docker/sandbox-templates:codex-docker`. These agent-matched variants provide Docker Engine and Docker Compose.
- Both harnesses expose Node.js `24.19.0`, Go `1.26.6`, OpenJDK 25, Maven, Gradle and the current full toolchain.
- Agent credentials and user configuration are managed by Docker Sandboxes; no secrets are baked into images or committed.
- Every shell script uses `set -euo pipefail` and preserves source-without-side-effects behavior.
- `claude-sbx` remains a working compatibility command.

---

## File Map

Create or modify these files:

```text
shared/install-system-toolchain.sh       # root-owned apt/runtime installs
shared/install-user-toolchain.sh         # agent-owned uv/Go installs
harnesses/claude-code/Dockerfile         # Claude-specific base + shared installers
harnesses/claude-code/kit/spec.yaml
harnesses/claude-code/bin/claude-code-sbx
harnesses/claude-code/scripts/bootstrap.sh
harnesses/claude-code/scripts/verify.sh
harnesses/codex/Dockerfile               # Codex-specific base + shared installers
harnesses/codex/kit/spec.yaml
harnesses/codex/bin/codex-sbx
harnesses/codex/scripts/bootstrap.sh
harnesses/codex/scripts/verify.sh
bin/claude-sbx                            # compatibility delegate
bin/claude-sbx-rebuild                    # Claude build delegate
bin/codex-sbx                             # Codex entrypoint delegate
bin/codex-sbx-rebuild                     # Codex build delegate
tests/test_harness_layout.sh
tests/test_codex_name.sh
tests/test_wrapper_wiring.sh
README.md
docs/usage.md
Makefile
```

Preserve the existing user changes and existing tests. Move Claude implementation files with `git mv` where possible, then update tests and references to the new paths.

### Task 1: Add shared toolchain installers

**Files:**
- Create: `shared/install-system-toolchain.sh`
- Create: `shared/install-user-toolchain.sh`
- Test: `tests/test_harness_layout.sh`

**Interfaces:**
- `install-system-toolchain.sh` runs as root with `NODE_VERSION` and `GO_VERSION` environment variables and installs apt packages, Node, Go, yq, Corepack/pnpm, GitHub CLI, Playwright CLI and Chromium dependencies.
- `install-user-toolchain.sh` runs as `agent` and installs uv plus the existing Go developer tools.

- [ ] **Step 1: Write the layout test**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for path in \
  "$ROOT/shared/install-system-toolchain.sh" \
  "$ROOT/shared/install-user-toolchain.sh"; do
  [[ -x "$path" ]] || { echo "missing executable: $path" >&2; exit 1; }
done
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `bash tests/test_harness_layout.sh`

Expected: FAIL because the shared installer files do not exist.

- [ ] **Step 3: Extract the existing Dockerfile commands**

Put all root-owned package installation and architecture-specific Node/Go/yq installation in `shared/install-system-toolchain.sh`. Require:

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${NODE_VERSION:?NODE_VERSION is required}"
: "${GO_VERSION:?GO_VERSION is required}"
```

Keep the existing package list, version values, architecture mapping, `JAVA_HOME`, `fd` symlink, GitHub CLI installation, Playwright CLI installation and Chromium installation intact.

- [ ] **Step 4: Extract user-owned installs**

Put the existing uv and Go `go install` commands in `shared/install-user-toolchain.sh`, preserving the `agent` user context and `PATH` assumptions.

- [ ] **Step 5: Run the focused test**

Run: `bash tests/test_harness_layout.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shared tests/test_harness_layout.sh
git commit -m "refactor: extract shared sandbox toolchain installers"
```

### Task 2: Move Claude into its harness boundary

**Files:**
- Move: `Dockerfile` → `harnesses/claude-code/Dockerfile`
- Move: `kit/spec.yaml` → `harnesses/claude-code/kit/spec.yaml`
- Move: `scripts/verify.sh` → `harnesses/claude-code/scripts/verify.sh`
- Move: implementation from `bin/claude-sbx` → `harnesses/claude-code/bin/claude-code-sbx`
- Modify: `bin/claude-sbx`
- Modify: existing Claude tests and `Makefile`

**Interfaces:**
- `harnesses/claude-code/bin/claude-code-sbx` exports the existing helper functions and runs the current Claude lifecycle.
- Root `bin/claude-sbx` resolves its own directory and `exec`s the harness implementation, so sourcing it still exposes helper functions for existing tests.

- [ ] **Step 1: Add the Claude Dockerfile test assertion**

Extend `tests/test_harness_layout.sh` with:

```bash
grep -Fq 'FROM docker/sandbox-templates:claude-code-docker' "$ROOT/harnesses/claude-code/Dockerfile"
grep -Fq 'install-system-toolchain.sh' "$ROOT/harnesses/claude-code/Dockerfile"
grep -Fq 'install-user-toolchain.sh' "$ROOT/harnesses/claude-code/Dockerfile"
```

- [ ] **Step 2: Move Claude files without changing behavior**

Use `git mv` for the existing Dockerfile, kit, bootstrap, verification and implementation. Rename the implementation entrypoint to `claude-code-sbx` and update its `ROOT`, `KIT`, `BOOTSTRAP`, `VERIFY` paths relative to `harnesses/claude-code/`. Do not leave a second root Dockerfile with an independent toolchain definition.

- [ ] **Step 3: Create the Claude Dockerfile**

Use:

```dockerfile
FROM docker/sandbox-templates:claude-code-docker

ARG NODE_VERSION=24.19.0
ARG GO_VERSION=1.26.6

COPY shared/install-system-toolchain.sh /tmp/install-system-toolchain.sh
RUN NODE_VERSION="$NODE_VERSION" GO_VERSION="$GO_VERSION" bash /tmp/install-system-toolchain.sh

COPY shared/install-user-toolchain.sh /tmp/install-user-toolchain.sh
USER agent
RUN bash /tmp/install-user-toolchain.sh
```

Ensure the shared scripts are copied using the build context expected by the rebuild wrapper.

- [ ] **Step 4: Create the compatibility delegate**

`bin/claude-sbx` must contain:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/harnesses/claude-code/bin/claude-code-sbx" "$@"
```

When sourced, it must source the implementation rather than `exec` it, so existing helper tests continue to work.

- [ ] **Step 5: Update Claude template/build references**

Set Claude’s template tag to `claude-sbx:local`, kit path to `harnesses/claude-code/kit`, and bootstrap/verification paths to the harness directory. Make `bin/claude-sbx-rebuild` build `harnesses/claude-code/Dockerfile` with the repository root as context and load `claude-sbx:local`.

- [ ] **Step 6: Run Claude host tests**

Run: `make test`

Expected: all existing Claude tests and `test_harness_layout.sh` pass without requiring `sbx` or a sandbox.

- [ ] **Step 7: Commit**

```bash
git add Dockerfile bin/claude-sbx bin/claude-sbx-rebuild kit scripts harnesses bin tests Makefile
git commit -m "refactor: isolate Claude Code harness"
```

### Task 3: Add the Codex harness

**Files:**
- Create: `harnesses/codex/Dockerfile`
- Create: `harnesses/codex/kit/spec.yaml`
- Create: `harnesses/codex/bin/codex-sbx`
- Create: `harnesses/codex/scripts/bootstrap.sh`
- Create: `harnesses/codex/scripts/verify.sh`
- Create: `bin/codex-sbx`
- Create: `bin/codex-sbx-rebuild`
- Create: `tests/test_codex_name.sh`
- Create: `tests/test_wrapper_wiring.sh`

**Interfaces:**
- `sandbox_name_for_repo` returns `codex-<slug>-<8hex>`.
- `codex-sbx` creates/reuses a Codex sandbox with `sbx create --name ... --template codex-sbx:local --kit ... codex ...` and attaches with `sbx run --name ...`.
- `harnesses/codex/scripts/bootstrap.sh` is idempotent and does not touch Claude configuration.

- [ ] **Step 1: Write failing Codex naming and wiring tests**

`tests/test_codex_name.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/harnesses/codex/bin/codex-sbx"
actual="$(sandbox_name_for_repo "/Users/example/dev/projects/my_app")"
[[ "$actual" =~ ^codex-my-app-[0-9a-f]{8}$ ]] || {
  echo "unexpected Codex sandbox name: $actual" >&2
  exit 1
}
```

`tests/test_wrapper_wiring.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grep -Fq 'FROM docker/sandbox-templates:codex-docker' "$ROOT/harnesses/codex/Dockerfile"
grep -Fq 'sbx create' "$ROOT/harnesses/codex/bin/codex-sbx"
grep -Fq 'codex-sbx:local' "$ROOT/harnesses/codex/bin/codex-sbx"
grep -Fq 'harnesses/codex' "$ROOT/bin/codex-sbx"
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `bash tests/test_codex_name.sh` and `bash tests/test_wrapper_wiring.sh`

Expected: FAIL because the Codex harness does not exist.

- [ ] **Step 3: Add the Codex Dockerfile**

Use the Codex-specific base and the same shared installers:

```dockerfile
FROM docker/sandbox-templates:codex-docker

ARG NODE_VERSION=24.19.0
ARG GO_VERSION=1.26.6

COPY shared/install-system-toolchain.sh /tmp/install-system-toolchain.sh
RUN NODE_VERSION="$NODE_VERSION" GO_VERSION="$GO_VERSION" bash /tmp/install-system-toolchain.sh

COPY shared/install-user-toolchain.sh /tmp/install-user-toolchain.sh
USER agent
RUN bash /tmp/install-user-toolchain.sh
```

- [ ] **Step 4: Implement Codex wrapper helpers**

Mirror the Claude wrapper’s `repo_root_from_cwd`, `ensure_worktrees_ignored`, `sandbox_exists`, `template_exists` and workspace mount behavior. Use `codex` as the create/run agent, `codex-sbx:local` as the template, `harnesses/codex/kit` as the kit, and the `codex-` name prefix. Preserve the same exit codes 2, 3 and 4 for non-Git, worktree-guard and missing-template failures.

- [ ] **Step 5: Add Codex kit and bootstrap**

Set `requires.agent: codex`, add the domains needed by the shared toolchain and Codex authentication flow, and include agent instructions for direct mounts, local worktrees, public-repo safety, project-local tooling and verification. The bootstrap script should only create a version marker under `$HOME/.cache/claude-sbx/codex-bootstrap-v1`; it must not run `claude`, install Claude plugins, or modify `.claude` files.

- [ ] **Step 6: Add Codex verification**

Check `codex`, the shared required commands, Java 25, Node `v24.19.0`, Go `1.26.6`, Docker Compose and the Codex-specific success message `codex-sbx verification passed`.

- [ ] **Step 7: Add the root Codex delegates**

`bin/codex-sbx` must delegate to the harness implementation. `bin/codex-sbx-rebuild` must build the Codex Dockerfile and load `codex-sbx:local`, using a separate `.build/codex-sbx.tar` output path.

- [ ] **Step 8: Run focused and full host tests**

Run: `bash tests/test_codex_name.sh`, `bash tests/test_wrapper_wiring.sh`, then `make test`.

Expected: all PASS without requiring an active sandbox.

- [ ] **Step 9: Commit**

```bash
git add harnesses/codex bin/codex-sbx bin/codex-sbx-rebuild tests
git commit -m "feat: add Codex Docker Sandbox harness"
```

### Task 4: Make the project public and document both harnesses

**Files:**
- Modify: `README.md`
- Modify: `docs/usage.md`
- Modify: `Makefile`
- Modify: `.gitignore`
- Modify: `tests/run.sh`

**Interfaces:**
- `make test` runs all host-side tests.
- `make rebuild-claude` and `make rebuild-codex` invoke the matching rebuild wrappers.
- Public docs explain common setup, Claude usage, Codex usage, authentication, ports, rebuilds, sandbox recreation and future harness extension points.

- [ ] **Step 1: Add public-repo ignore rules**

Keep `.build/`, `.DS_Store`, `.idea/` and `.worktrees/`. Ignore local environment files and generated sandbox exports. Do not blanket-ignore `.claude/`, `.codex/`, `.playwright/` or `.serena/`: inspect each existing directory and preserve project-level instructions/configuration that belongs in a public repository.

- [ ] **Step 2: Update Make targets**

Use:

```make
.PHONY: test verify rebuild-claude rebuild-codex

test:
	./tests/run.sh

verify:
	./harnesses/claude-code/scripts/verify.sh

rebuild-claude:
	./bin/claude-sbx-rebuild

rebuild-codex:
	./bin/codex-sbx-rebuild
```

Keep `rebuild` as an alias for `rebuild-claude` for compatibility.

- [ ] **Step 3: Rewrite README and usage docs**

Use public-neutral language. Show:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
claude-sbx
codex-sbx
```

Document that `sbx secret set openai --oauth` or the interactive `sbx run codex` flow manages Codex credentials on the host, while Claude authentication is likewise not baked into the image. Document separate sandbox names and the unchanged `.worktrees/` guard.

- [ ] **Step 4: Run documentation/layout checks**

Run:

```bash
make test
rg -n 'private Mac|API_KEY|token|secret|claude-.*codex|--clone' README.md docs/usage.md harnesses bin
```

Expected: no committed credential values; `--clone` appears only in explanatory text saying it is not used; no private-machine wording remains.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/usage.md Makefile .gitignore tests
git commit -m "docs: publish Claude and Codex harness usage"
```

### Task 5: Verify both sandbox builds and lifecycle smoke tests

**Files:**
- Modify: `harnesses/claude-code/scripts/verify.sh`
- Modify: `harnesses/codex/scripts/verify.sh`
- Modify: `docs/usage.md`

- [ ] **Step 1: Build both templates**

Run:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
```

Expected: both images build, export to distinct `.build/*.tar` files, and load into the SBX template store under `claude-sbx:local` and `codex-sbx:local`.

- [ ] **Step 2: Create one test sandbox per harness**

From a disposable Git repository with `.worktrees/` ignored, run `claude-sbx` and `codex-sbx` once each. Confirm `sbx ls` shows two names with the same repo slug but different `claude-` and `codex-` prefixes.

- [ ] **Step 3: Run inside-sandbox verification**

Run the Claude verification through `sbx exec <claude-name> bash <mounted-repo>/harnesses/claude-code/scripts/verify.sh` and the Codex equivalent. Expected: both report their harness-specific success messages.

- [ ] **Step 4: Reattach and test direct mounts**

Run each wrapper a second time, create a file from the agent session, and verify the file is visible at the original host path. Do not pass `--clone`.

- [ ] **Step 5: Remove only disposable test sandboxes**

Use `sbx rm` with the two exact test sandbox names after verification. Do not remove existing user sandboxes.

- [ ] **Step 6: Commit final verification adjustments**

```bash
git add harnesses docs
git commit -m "test: verify independent Claude and Codex sandboxes"
```

## Self-review checklist

- [ ] Every acceptance criterion in `docs/superpowers/specs/2026-08-26-multi-harness-design.md` maps to at least one task above.
- [ ] No task depends on a file or function not defined in this plan.
- [ ] Claude and Codex template bases are agent-matched.
- [ ] Root compatibility commands are preserved.
- [ ] No implementation task uses `--clone`.
- [ ] Host tests do not require Docker Sandboxes.
- [ ] Inside-sandbox verification is explicitly separate from host tests.

# OpenCode Docker Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add isolated, provider-agnostic OpenCode Docker Sandbox support with shared tooling, MCP integrations, agent skills, lifecycle tests, and public documentation.

**Architecture:** Add `harnesses/opencode/` as an independent harness based on the official `opencode-docker` template. Reuse shared toolchain installers and the existing direct-mount launcher contract, but use unique OpenCode template, kit, prefix, config state, and sandbox identity. Configure Serena and Context7 through global OpenCode JSON config and expose Superpowers, Caveman, and Playwright through global agent-compatible skills.

**Tech Stack:** Bash, Dockerfiles, Docker Sandboxes `sbx`, YAML kit specs, OpenCode CLI, jq, shell host tests, Node `24.19.0`, Go `1.26.6`, OpenJDK `25`.

**Spec:** `docs/superpowers/specs/2026-09-05-opencode-sbx-design.md`

## Global Constraints

- Base image: `docker/sandbox-templates:opencode-docker`.
- Template tag: `opencode-sbx:local`.
- Sandbox name: `opencode-<repo-slug>-<8-hex-path-digest>`.
- Required runtime pins: Node `24.19.0`, Go `1.26.6`, OpenJDK `25`.
- Target repository mounts read/write; harness repository mounts read-only when different.
- `.worktrees/` must be ignored by Git; launcher exits `3` otherwise.
- OpenCode must not reuse Claude Code or Codex template, sandbox, config, or state.
- No credentials, API keys, session state, generated images, or machine-specific paths in tracked files.
- Bootstrap must be idempotent and preserve existing user configuration.
- Host completion command: `make test`.
- Do not commit unless user explicitly requests a commit.

---

### Task 1: Add OpenCode Contract Tests First

**Files:**
- Create: `tests/test_opencode_name.sh`
- Create: `tests/test_opencode_lifecycle.sh`
- Modify: `tests/test_harness_layout.sh`
- Modify: `tests/test_wrapper_wiring.sh`
- Modify: `tests/test_public_wiring.sh`
- Modify: `tests/test_root_wrapper_symlinks.sh`

**Interfaces:**
- Consumes: the existing Codex host-test conventions and the future files under `harnesses/opencode/`.
- Produces: executable assertions for OpenCode naming, mount policy, lifecycle commands, layout, and public wiring.

- [ ] **Step 1: Add deterministic naming test.**

Create `tests/test_opencode_name.sh` with the same temporary path input used by `tests/test_codex_name.sh`, source `harnesses/opencode/bin/opencode-sbx`, and assert:

```bash
actual="$(sandbox_name_for_repo "/Users/example/dev/projects/my_app")"
[[ "$actual" == "opencode-my-app-2ed5b256" ]]
```

- [ ] **Step 2: Add lifecycle mock test.**

Copy the structure of `tests/test_codex_lifecycle.sh` into `tests/test_opencode_lifecycle.sh` and change every harness-specific assertion to OpenCode:

```bash
source "$ROOT/harnesses/opencode/bin/opencode-sbx"
grep -Fq "sbx create --name $name --template opencode-sbx:local --kit $ROOT/harnesses/opencode/kit opencode $repo $ROOT:ro" "$MOCK_LOG"
grep -Fq "sbx exec $name bash $ROOT/harnesses/opencode/scripts/bootstrap.sh" "$MOCK_LOG"
grep -Fq "sbx run --name $name" "$MOCK_LOG"
```

Retain checks that an unignored `.worktrees/` directory is rejected and that `workspace_mounts` returns target plus `$ROOT:ro` for an external repository.

- [ ] **Step 3: Extend layout, wrapper, and public wiring assertions.**

Add assertions for:

```bash
grep -Fq 'FROM docker/sandbox-templates:opencode-docker' "$ROOT/harnesses/opencode/Dockerfile"
grep -Fq 'harnesses/opencode' "$ROOT/bin/opencode-sbx"
grep -Fq 'opencode-sbx:local' "$ROOT/harnesses/opencode/bin/opencode-sbx"
grep -Fq 'opencode-sbx-rebuild' "$ROOT/README.md"
grep -Fq 'opencode-sbx' "$ROOT/docs/usage.md"
```

Add `rebuild-opencode` and `verify-opencode` to the Makefile target list checked by `test_public_wiring.sh`.

- [ ] **Step 4: Run only new/changed tests and confirm expected failure.**

Run:

```bash
bash tests/test_opencode_name.sh
bash tests/test_opencode_lifecycle.sh
bash tests/test_harness_layout.sh
bash tests/test_wrapper_wiring.sh
bash tests/test_public_wiring.sh
```

Expected: failure because OpenCode harness files and root wiring do not exist yet. Do not weaken assertions to make this step pass prematurely.

---

### Task 2: Implement OpenCode Launcher and Root Entrypoints

**Files:**
- Create: `harnesses/opencode/bin/opencode-sbx`
- Create: `bin/opencode-sbx`
- Create: `bin/opencode-sbx-rebuild`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `sbx`, Git, target repository, OpenCode kit paths, bootstrap path, and verify path.
- Produces: `sandbox_name_for_repo`, `repo_root_from_cwd`, `ensure_worktrees_ignored`, `sandbox_exists`, `template_exists`, `workspace_mounts`, `bootstrap_sandbox`, `verify_sandbox`, and `main` with OpenCode-specific constants.

- [ ] **Step 1: Create harness launcher from the Codex lifecycle contract.**

Copy `harnesses/codex/bin/codex-sbx` and set these constants and command values:

```bash
TEMPLATE="opencode-sbx:local"
KIT="$ROOT/harnesses/opencode/kit"
BOOTSTRAP="$ROOT/harnesses/opencode/scripts/bootstrap.sh"
VERIFY="$ROOT/harnesses/opencode/scripts/verify.sh"
```

Change the naming function to print `opencode-%s-%s`, the template query to match `opencode-sbx`, the `sbx create` agent argument to `opencode`, and all user-facing errors to start with `opencode-sbx:`. Preserve source-safe behavior: `main` runs only when the file is executed, not when sourced.

- [ ] **Step 2: Create root delegate.**

Create `bin/opencode-sbx` using the same symlink resolution and source-vs-exec behavior as `bin/codex-sbx`, delegating to `harnesses/opencode/bin/opencode-sbx`.

- [ ] **Step 3: Create rebuild delegate.**

Create `bin/opencode-sbx-rebuild` using `bin/codex-sbx-rebuild` as the structure. Set:

```bash
IMAGE="opencode-sbx:local"
TAR="$BUILD_DIR/opencode-sbx.tar"
```

Retain source guard, `.build/` creation, existing-template removal, `sbx template load`, and success output.

- [ ] **Step 4: Add Make targets.**

Extend `.PHONY` and add:

```make
verify-opencode:
	./harnesses/opencode/scripts/verify.sh

rebuild-opencode:
	./bin/opencode-sbx-rebuild
```

Keep existing `verify`, `rebuild`, `rebuild-claude`, and `rebuild-codex` behavior unchanged.

- [ ] **Step 5: Run lifecycle tests.**

Run:

```bash
bash tests/test_opencode_name.sh
bash tests/test_opencode_lifecycle.sh
bash tests/test_rebuild_symlink.sh
bash tests/test_root_wrapper_symlinks.sh
```

Expected: PASS for OpenCode lifecycle and source-safe wrapper checks. Layout tests may still fail until the image and kit exist.

---

### Task 3: Add OpenCode Image and Kit

**Files:**
- Create: `harnesses/opencode/Dockerfile`
- Create: `harnesses/opencode/kit/spec.yaml`

**Interfaces:**
- Consumes: `shared/install-system-toolchain.sh` and `shared/install-user-toolchain.sh`.
- Produces: a loaded OpenCode-compatible image with shared pinned tooling and a creation-time kit with OpenCode network/instruction policy.

- [ ] **Step 1: Create Dockerfile.**

Use the same installer ordering and user transitions as `harnesses/codex/Dockerfile`:

```dockerfile
FROM docker/sandbox-templates:opencode-docker

ARG NODE_VERSION=24.19.0
ARG GO_VERSION=1.26.6

USER root
ENV PATH=/usr/local/go/bin:/home/agent/go/bin:${PATH}

COPY shared/install-system-toolchain.sh /tmp/install-system-toolchain.sh
RUN NODE_VERSION="$NODE_VERSION" GO_VERSION="$GO_VERSION" bash /tmp/install-system-toolchain.sh

COPY shared/install-user-toolchain.sh /tmp/install-user-toolchain.sh
USER agent
RUN bash /tmp/install-user-toolchain.sh
```

- [ ] **Step 2: Create kit metadata and network policy.**

Set `name: opencode-sbx`, `displayName: OpenCode SBX`, `requires.agent: opencode`, and include domains needed by existing shared installers plus OpenCode and configured MCP/provider traffic:

```yaml
      - github.com
      - api.github.com
      - raw.githubusercontent.com
      - objects.githubusercontent.com
      - codeload.github.com
      - registry.npmjs.org
      - nodejs.org
      - go.dev
      - proxy.golang.org
      - sum.golang.org
      - pypi.org
      - files.pythonhosted.org
      - astral.sh
      - mcp.context7.com
      - cdn.playwright.dev
      - playwright.download.prss.microsoft.com
      - opencode.ai
      - api.openai.com
      - auth.openai.com
      - chatgpt.com
      - platform.openai.com
      - api.anthropic.com
      - generativelanguage.googleapis.com
      - api.x.ai
      - api.groq.com
      - openrouter.ai
      - api.openrouter.ai
```

Add agent instructions for direct mounts, project-local `.worktrees/`, Serena activation when changing worktrees, public-repository safety, repository-local tool versions, and Playwright CLI usage. Keep instructions concise and OpenCode-specific.

- [ ] **Step 3: Run image/kit wiring tests.**

Run:

```bash
bash tests/test_harness_layout.sh
bash tests/test_wrapper_wiring.sh
```

Expected: PASS. Do not run a Docker build until host tests pass and Docker availability is checked.

---

### Task 4: Implement Idempotent OpenCode Bootstrap

**Files:**
- Create: `harnesses/opencode/scripts/bootstrap.sh`
- Create: `tests/test_opencode_bootstrap.sh`

**Interfaces:**
- Consumes: installed `serena`, `jq`, `git`, `playwright-cli`, GitHub network access, and OpenCode global config directory.
- Produces: `ensure_opencode_config <config_file>`, `ensure_git_checkout <directory> <url> [<ref>]`, configured MCP entries, global skills, and a bootstrap marker.

- [ ] **Step 1: Write config helper tests.**

Create a source-safe test that sources the bootstrap (the script must return before network actions when sourced), creates a temporary JSON config, and calls the helper. Assert additive entries without deleting an existing key:

```bash
config="$tmp/opencode.json"
printf '{"model":"existing","mcp":{"custom":{"type":"remote","url":"https://example.test/mcp"}}}\n' >"$config"
ensure_opencode_config "$config"
jq -e '.model == "existing" and .mcp.custom.url == "https://example.test/mcp"' "$config" >/dev/null
jq -e '.mcp.serena.type == "local" and .mcp.context7.url == "https://mcp.context7.com/mcp"' "$config" >/dev/null
```

Also assert that a missing file is created and that an invalid JSON file fails without replacing it.

- [ ] **Step 2: Run bootstrap helper tests and confirm failure.**

Run:

```bash
bash tests/test_opencode_bootstrap.sh
```

Expected: FAIL because the helpers do not exist.

- [ ] **Step 3: Implement additive OpenCode config.**

Define `ensure_opencode_config` before the source guard. Use `jq` and a temporary file in the same directory. Preserve all existing JSON keys and merge only these deterministic entries:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "serena": {
      "type": "local",
      "command": ["serena", "start-mcp-server", "--context=ide-assistant", "--project-from-cwd"],
      "enabled": true
    },
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "enabled": true
    }
  }
}
```

If the target file exists and is not valid JSON, print a path-specific error and exit nonzero; never truncate or replace it. If `opencode.jsonc` already exists, leave it untouched and manage `config.json` as the additive managed file, separate from kit-generated `opencode.json`. Parse JSONC comments/trailing commas and fail before writing when its `serena` or `context7` entry conflicts with the managed value.

- [ ] **Step 4: Implement idempotent repository checkout helper.**

Define `ensure_git_checkout` with behavior matching Codex bootstrap: pull an existing Git checkout fast-forward only; clone Superpowers with `--depth=1` from `https://github.com/obra/superpowers.git`; clone Caveman with `--depth=1 --branch v2.2.0` from `https://github.com/JuliusBrussee/caveman.git`; refuse to replace an existing non-git path. Use isolated paths:

```bash
superpowers_dir="$HOME/.opencode/superpowers"
caveman_dir="$HOME/.opencode/caveman"
```

Use Superpowers default branch and the pinned Caveman tag/revision already used by Codex (`v2.2.0`, revision `9aa63945a349bef17206540650db48c30fafbdf2`).

- [ ] **Step 5: Implement skill links and marker.**

Create `~/.agents/skills`, link:

```bash
ln -sfn "$superpowers_dir/skills" "$HOME/.agents/skills/superpowers"
ln -sfn "$caveman_dir/skills/caveman" "$HOME/.agents/skills/caveman"
playwright-cli install --skills agents --global
```

Create `~/.config/opencode`, call `ensure_opencode_config "$HOME/.config/opencode/config.json"`, create `~/.cache/claude-sbx`, and touch `opencode-bootstrap-v1`. End with `OpenCode bootstrap setup complete.`

- [ ] **Step 6: Run bootstrap tests twice.**

Run:

```bash
bash tests/test_opencode_bootstrap.sh
bash tests/test_opencode_bootstrap.sh
```

Expected: PASS both times; second run must not duplicate JSON entries or reject valid existing Git checkouts.

---

### Task 5: Add OpenCode Verification

**Files:**
- Create: `harnesses/opencode/scripts/verify.sh`
- Create: `tests/test_opencode_verify_wiring.sh`

**Interfaces:**
- Consumes: OpenCode bootstrap output and shared installed toolchain.
- Produces: nonzero diagnostics for missing OpenCode command, tool, version, MCP configuration, or skill; success line `opencode-sbx verification passed`.

- [ ] **Step 1: Add static verify wiring test.**

Assert the script checks `opencode`, `serena`, `playwright-cli`, shared commands, pinned Node/Go/Java versions, Docker Compose, `opencode debug config`, and all three skill paths:

```bash
grep -Fq 'opencode' "$ROOT/harnesses/opencode/scripts/verify.sh"
grep -Fq 'opencode debug config' "$ROOT/harnesses/opencode/scripts/verify.sh"
grep -Fq 'superpowers' "$ROOT/harnesses/opencode/scripts/verify.sh"
grep -Fq 'caveman' "$ROOT/harnesses/opencode/scripts/verify.sh"
grep -Fq 'playwright-cli' "$ROOT/harnesses/opencode/scripts/verify.sh"
```

- [ ] **Step 2: Implement command and version checks.**

Use the Codex required command list with `opencode` replacing `codex`. Keep checks for Java/Javac `25`, Node exactly `v24.19.0`, Go containing `go1.26.6`, Maven, Gradle, and `docker compose version`.

- [ ] **Step 3: Implement resolved config and skill checks.**

Capture `config="$(opencode debug config)"` and validate with `jq -e` that `.mcp.serena.type == "local"`, `.mcp.context7.type == "remote"`, and `.mcp.context7.url == "https://mcp.context7.com/mcp"`. Check:

```bash
[[ -f "$HOME/.agents/skills/superpowers/README.md" || -d "$HOME/.agents/skills/superpowers" ]]
[[ -f "$HOME/.agents/skills/caveman/SKILL.md" ]]
[[ -f "$HOME/.agents/skills/playwright-cli/SKILL.md" ]]
```

Use harness-specific error messages and finish with `echo "opencode-sbx verification passed"`.

- [ ] **Step 4: Run static and shell validation.**

Run:

```bash
bash tests/test_opencode_verify_wiring.sh
bash -n harnesses/opencode/scripts/bootstrap.sh harnesses/opencode/scripts/verify.sh
```

Expected: PASS.

---

### Task 6: Update Public Documentation and Complete Host Wiring

**Files:**
- Modify: `README.md`
- Modify: `docs/usage.md`
- Modify: `tests/test_public_wiring.sh`
- Modify: `tests/test_harness_layout.sh`
- Modify: `tests/test_wrapper_wiring.sh`

**Interfaces:**
- Consumes: finalized OpenCode command names, template tag, auth policy, verification command, and rebuild lifecycle.
- Produces: public instructions consistent with implementation and tests that fail if future wiring drifts.

- [ ] **Step 1: Update README quick start.**

Change the title and supported-harness summary to include OpenCode. Add the rebuild symlink and launch examples:

```bash
./bin/opencode-sbx-rebuild
ln -sfn "$PWD/bin/opencode-sbx" "$HOME/.local/bin/opencode-sbx"
ln -sfn "$PWD/bin/opencode-sbx-rebuild" "$HOME/.local/bin/opencode-sbx-rebuild"
```

Keep existing Claude/Codex instructions intact.

- [ ] **Step 2: Add OpenCode usage/auth/verify sections.**

Document `sbx secret set` provider commands, OpenCode Zen custom secret handling, direct mount and `.worktrees/` guard, deterministic name/template table, `make rebuild-opencode`, `sbx rm` after kit/image changes, and:

```bash
source /path/to/claude-sbx/bin/opencode-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash /path/to/claude-sbx/harnesses/opencode/scripts/verify.sh
```

State clearly that host-level OpenCode config is not inherited; bootstrap creates managed global config inside the sandbox.

- [ ] **Step 3: Add public assertions.**

Assert OpenCode appears in README/docs, the template and deterministic prefix are documented, Make targets exist, and the provider/auth wording contains no secret values or private machine paths.

- [ ] **Step 4: Run complete host suite.**

Run:

```bash
make test
```

Expected: every existing and new test passes. If a pre-existing dirty-file test fails, inspect the failure and preserve the user's unrelated changes.

---

### Task 7: Optional Docker Sandbox Smoke Verification

**Files:**
- No tracked files unless a concrete allowlist or runtime issue requires a focused fix.

- [ ] **Step 1: Check local prerequisites.**

Run:

```bash
sbx version
docker version
```

- [ ] **Step 2: Build/load OpenCode template.**

Run:

```bash
./bin/opencode-sbx-rebuild
```

Expected: `opencode-sbx:local` is loaded by `sbx template ls`.

- [ ] **Step 3: Recreate the target sandbox.**

From a target Git repository with `.worktrees/` ignored, calculate the name and remove only that OpenCode sandbox:

```bash
source /path/to/claude-sbx/bin/opencode-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx rm "$name" 2>/dev/null || true
opencode-sbx
```

- [ ] **Step 4: Run inside-sandbox verify.**

Run:

```bash
sbx exec "$name" bash /path/to/claude-sbx/harnesses/opencode/scripts/verify.sh
```

Expected: `opencode-sbx verification passed`. If network policy blocks bootstrap/provider traffic, inspect `sbx policy log "$name"`, add only the required domain to the OpenCode kit, and recreate the sandbox.

---

## Plan Self-Review

- Spec coverage: dedicated image/kit/lifecycle in Tasks 2-3; MCP and skills in Task 4; verification in Task 5; docs/auth/security in Task 6; acceptance smoke path in Task 7.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation step remains.
- Interface consistency: launcher constants and command names are fixed in Task 2 and reused by tests, docs, rebuild, kit, and verification.
- Existing worktree safety: all implementation tasks limit edits to OpenCode additions and explicit wiring files; unrelated dirty files remain untouched.

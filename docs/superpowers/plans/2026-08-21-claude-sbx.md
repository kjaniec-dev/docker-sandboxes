# Claude SBX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable `claude-sbx` launcher for a private macOS development machine that runs Claude Code inside Docker Sandboxes with direct host workspace mounting, Superpowers, Caveman, Frontend Design, Context7, Serena, Playwright skills, Go/Node/Python tooling, and no Java toolchain.

**Architecture:** A custom Docker Sandbox template based on `docker/sandbox-templates:claude-code-minimal-docker` contains the heavyweight CLI/toolchain layer. A small schema-v2 Docker SBX mixin kit provides Claude instructions and required network access. A post-create bootstrap configures Claude-managed plugins/skills idempotently, while a host-side Bash wrapper creates or reattaches to one deterministic sandbox per Git repository.

**Tech Stack:** Bash, Dockerfile, Docker Desktop, Docker Sandboxes (`sbx`), Claude Code plugins, Docker SBX Kit schema v2, Node.js 24.19.0 LTS, pnpm/Corepack, Python 3 + uv, Go 1.26.6, Playwright CLI + Chromium, Docker Engine/Compose.

**Spec:** `docs/superpowers/specs/2026-08-21-claude-sbx-design.md`

## Global Constraints

- Host target is macOS with Docker Desktop and the `sbx` CLI installed.
- Use Docker Sandboxes direct workspace mode; never pass `--clone`.
- The selected Git repository is mounted read/write so JetBrains IDEs see Claude edits immediately.
- Superpowers worktrees live under `<repo>/.worktrees/`.
- Refuse to start if `.worktrees/` is not ignored by Git.
- Use `docker/sandbox-templates:claude-code-minimal-docker` as the template base.
- Keep Docker Engine inside the sandbox.
- Do not install Java, Maven, or Gradle.
- Pin Node.js runtime to `24.19.0` LTS.
- Pin Go runtime to `1.26.6`.
- Install project-specific frontend/Python dependencies from each repository; do not globally install TypeScript, ESLint, Prettier, Next.js, Vite, pytest, Ruff, or similar repo-owned tools.
- Install Caveman only through its Claude plugin path; do not run its standalone hook installer because that can duplicate hooks.
- Treat `frontend-design@claude-plugins-official` reporting version `unknown` as acceptable until Anthropic adds a version field.
- Use Context7 and Serena from `claude-plugins-official`.
- Use Playwright CLI + installed skills rather than Playwright MCP by default.
- Serena must activate the current checkout when a session starts and re-activate the current worktree after changing worktrees.
- Custom template tag is `claude-sbx:local`.
- All bootstrap scripts must be idempotent.
- All shell scripts use `set -euo pipefail`.

---

## File Map

Create this repository layout:

```text
claude-sbx/
├── .gitignore
├── Dockerfile
├── Makefile
├── README.md
├── bin/
│   ├── claude-sbx
│   └── claude-sbx-rebuild
├── kit/
│   └── spec.yaml
├── scripts/
│   ├── bootstrap-claude.sh
│   └── verify.sh
├── tests/
│   ├── run.sh
│   ├── test_name.sh
│   ├── test_worktree_guard.sh
│   └── test_bootstrap_helpers.sh
└── docs/
    ├── usage.md
    └── superpowers/
        ├── specs/
        │   └── 2026-08-21-claude-sbx-design.md
        └── plans/
            └── 2026-08-21-claude-sbx.md
```

Responsibilities:

- `Dockerfile` — reusable sandbox image/toolchain only; no repo-specific state and no Claude user settings.
- `kit/spec.yaml` — mixin instructions and egress policy applied only when a sandbox is first created.
- `bin/claude-sbx` — repo detection, worktree safety check, sandbox lifecycle, bootstrap, attach.
- `bin/claude-sbx-rebuild` — build image, export it, load it into the SBX template store.
- `scripts/bootstrap-claude.sh` — idempotent Claude plugin and Playwright-skill configuration.
- `scripts/verify.sh` — toolchain/integration smoke checks inside the sandbox.
- `tests/*.sh` — host-side unit tests for deterministic naming, ignore guard, and bootstrap helper behavior.
- `docs/usage.md` — installation, daily use, rebuild, worktree, IntelliJ, ports, and troubleshooting instructions.

---

### Task 1: Repository skeleton and shell test harness

**Files:**
- Create: `.gitignore`
- Create: `Makefile`
- Create: `tests/run.sh`
- Create: `tests/test_name.sh`
- Create: `tests/test_worktree_guard.sh`
- Create: `tests/test_bootstrap_helpers.sh`
- Create: `docs/superpowers/specs/2026-08-21-claude-sbx-design.md`
- Create: `docs/superpowers/plans/2026-08-21-claude-sbx.md`

**Interfaces:**
- Consumes: approved design document.
- Produces: `make test`, which runs every `tests/test_*.sh` file and fails on the first test failure.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.build/
.DS_Store
```

- [ ] **Step 2: Create the failing test runner**

`tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for test_file in "$ROOT"/tests/test_*.sh; do
  echo "==> $(basename "$test_file")"
  bash "$test_file"
done
```

Make it executable:

```bash
chmod +x tests/run.sh
```

- [ ] **Step 3: Create `Makefile`**

```make
.PHONY: test verify rebuild

test:
	./tests/run.sh

verify:
	./scripts/verify.sh

rebuild:
	./bin/claude-sbx-rebuild
```

- [ ] **Step 4: Create initial tests that fail because implementation files do not exist**

`tests/test_name.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/claude-sbx"

actual="$(sandbox_name_for_repo "/Users/example/dev/projects/my_app")"

case "$actual" in
  claude-my-app-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *)
    echo "unexpected sandbox name: $actual" >&2
    exit 1
    ;;
esac
```

`tests/test_worktree_guard.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/claude-sbx"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
touch "$tmp/.gitignore"

if ensure_worktrees_ignored "$tmp"; then
  echo "guard should fail when .worktrees/ is not ignored" >&2
  exit 1
fi

printf '.worktrees/\n' >> "$tmp/.gitignore"
ensure_worktrees_ignored "$tmp"
```

`tests/test_bootstrap_helpers.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/bootstrap-claude.sh"

plugin_list=$'superpowers@claude-plugins-official\ncontext7@claude-plugins-official'
plugin_is_installed "superpowers@claude-plugins-official" "$plugin_list"
! plugin_is_installed "frontend-design@claude-plugins-official" "$plugin_list"
```

Make them executable:

```bash
chmod +x tests/test_*.sh
```

- [ ] **Step 5: Run the test suite and verify it fails**

Run:

```bash
make test
```

Expected: FAIL because `bin/claude-sbx` and `scripts/bootstrap-claude.sh` do not exist yet.

- [ ] **Step 6: Copy the approved design and this plan into the documented paths**

The approved design must be saved verbatim as:

```text
docs/superpowers/specs/2026-08-21-claude-sbx-design.md
```

This plan must be saved as:

```text
docs/superpowers/plans/2026-08-21-claude-sbx.md
```

- [ ] **Step 7: Commit**

```bash
git add .gitignore Makefile tests docs/superpowers
git commit -m "chore: scaffold claude sbx project"
```

---

### Task 2: Deterministic repo naming and worktree safety

**Files:**
- Create: `bin/claude-sbx`
- Test: `tests/test_name.sh`
- Test: `tests/test_worktree_guard.sh`

**Interfaces:**
- Consumes: a Git repository path.
- Produces:
  - `sandbox_name_for_repo <absolute-repo-path>` → deterministic `claude-<slug>-<8hex>` name.
  - `ensure_worktrees_ignored <repo-root>` → success only when `.worktrees/` is ignored.
  - `repo_root_from_cwd` → absolute Git top-level directory.

- [ ] **Step 1: Implement only the reusable helper functions**

`bin/claude-sbx`:

```bash
#!/usr/bin/env bash
set -euo pipefail

sandbox_name_for_repo() {
  local repo_root="$1"
  local base slug digest

  base="$(basename "$repo_root")"
  slug="$(printf '%s' "$base" \
    | tr '[:upper:]_' '[:lower:]-' \
    | sed -E 's/[^a-z0-9.+-]+/-/g; s/^-+//; s/-+$//')"
  digest="$(printf '%s' "$repo_root" | shasum -a 256 | awk '{print substr($1,1,8)}')"

  printf 'claude-%s-%s\n' "$slug" "$digest"
}

repo_root_from_cwd() {
  git rev-parse --show-toplevel
}

ensure_worktrees_ignored() {
  local repo_root="$1"
  git -C "$repo_root" check-ignore -q .worktrees/
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  :
fi
```

Make executable:

```bash
chmod +x bin/claude-sbx
```

- [ ] **Step 2: Run naming and guard tests**

Run:

```bash
bash tests/test_name.sh
bash tests/test_worktree_guard.sh
```

Expected: PASS.

- [ ] **Step 3: Add non-Git error behavior**

Replace the bottom block with:

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if ! repo_root="$(repo_root_from_cwd 2>/dev/null)"; then
    echo "claude-sbx: run this command from inside a Git repository" >&2
    exit 2
  fi

  if ! ensure_worktrees_ignored "$repo_root"; then
    cat >&2 <<'EOF'
claude-sbx: .worktrees/ is not ignored by Git.

Add this line to the repository's .gitignore:

.worktrees/

Then run claude-sbx again.
EOF
    exit 3
  fi
fi
```

- [ ] **Step 4: Verify manually with a fixture**

Run:

```bash
tmp="$(mktemp -d)"
git -C "$tmp" init -q
(cd "$tmp" && /absolute/path/to/claude-sbx/bin/claude-sbx)
```

Expected: exit code `3` and message instructing the user to add `.worktrees/`.

Then:

```bash
printf '.worktrees/\n' > "$tmp/.gitignore"
(cd "$tmp" && /absolute/path/to/claude-sbx/bin/claude-sbx)
```

Expected at this stage: helper guard passes; later tasks add SBX lifecycle behavior.

- [ ] **Step 5: Commit**

```bash
git add bin/claude-sbx tests/test_name.sh tests/test_worktree_guard.sh
git commit -m "feat: add repository and worktree guards"
```

---

### Task 3: Custom Claude sandbox template

**Files:**
- Create: `Dockerfile`
- Create: `bin/claude-sbx-rebuild`

**Interfaces:**
- Produces Docker image/template `claude-sbx:local`.
- Provides commands:
  - `node --version` → `v24.19.0`
  - `go version` → `go1.26.6`
  - `python3 --version`
  - `uv --version`
  - `pnpm --version`
  - `docker compose version`
  - `gopls`, `goimports`, `golangci-lint`, `staticcheck`, `govulncheck`, `dlv`
  - core CLI and DB clients from the spec.
- Must not provide `java`, `mvn`, or `gradle`.

- [ ] **Step 1: Create `Dockerfile` with system packages and architecture mapping**

```dockerfile
FROM docker/sandbox-templates:claude-code-minimal-docker

ARG NODE_VERSION=24.19.0
ARG GO_VERSION=1.26.6

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
ENV PATH="/usr/local/go/bin:/home/agent/go/bin:/home/agent/.local/bin:${PATH}"

USER root

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      wget \
      gnupg \
      openssh-client \
      git \
      git-lfs \
      ripgrep \
      fd-find \
      jq \
      fzf \
      make \
      just \
      unzip \
      zip \
      tar \
      xz-utils \
      tree \
      shellcheck \
      shfmt \
      python3 \
      python3-venv \
      python3-pip \
      postgresql-client \
      sqlite3 \
      redis-tools \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) node_arch="x64"; go_arch="amd64" ;; \
      arm64) node_arch="arm64"; go_arch="arm64" ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    tar -xJf "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -C /usr/local --strip-components=1; \
    rm "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    curl -fsSLO "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz"; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-${go_arch}.tar.gz"; \
    rm "go${GO_VERSION}.linux-${go_arch}.tar.gz"

RUN corepack enable \
 && corepack prepare pnpm@10 --activate \
 && npm install -g @playwright/cli@latest \
 && npx -y playwright@latest install --with-deps chromium \
 && chmod -R a+rX /opt/ms-playwright

USER agent

RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
 && go install golang.org/x/tools/gopls@latest \
 && go install golang.org/x/tools/cmd/goimports@latest \
 && go install honnef.co/go/tools/cmd/staticcheck@latest \
 && go install golang.org/x/vuln/cmd/govulncheck@latest \
 && go install github.com/go-delve/delve/cmd/dlv@latest \
 && go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest

USER root

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

USER agent
```

- [ ] **Step 2: Build the image**

Run:

```bash
docker build -t claude-sbx:local .
```

Expected: build succeeds for the Mac's Docker architecture.

- [ ] **Step 3: Smoke-test the image before loading it into SBX**

Run:

```bash
docker run --rm claude-sbx:local bash -lc '
set -e
node --version
go version
python3 --version
uv --version
pnpm --version
git --version
gh --version
rg --version
fd --version
jq --version
yq --version || true
docker --version
docker compose version
psql --version
sqlite3 --version
redis-cli --version
gopls version
staticcheck -version
govulncheck -version
dlv version
'
```

If `yq` is absent on the base Ubuntu package set, add this explicit install before switching back to `USER agent`:

```dockerfile
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) yq_arch="amd64" ;; \
      arm64) yq_arch="arm64" ;; \
      *) exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}" \
      -o /usr/local/bin/yq; \
    chmod +x /usr/local/bin/yq
```

Then rebuild and re-run the smoke test.

- [ ] **Step 4: Assert Java tooling is absent**

Run:

```bash
docker run --rm claude-sbx:local bash -lc '
! command -v java
! command -v mvn
! command -v gradle
'
```

Expected: PASS.

- [ ] **Step 5: Create `bin/claude-sbx-rebuild`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
IMAGE="claude-sbx:local"
TAR="$BUILD_DIR/claude-sbx.tar"

mkdir -p "$BUILD_DIR"

docker build -t "$IMAGE" "$ROOT"
docker image save "$IMAGE" -o "$TAR"

if sbx template ls | grep -Fq "$IMAGE"; then
  sbx template rm "$IMAGE"
fi

sbx template load "$TAR"

echo "Loaded Docker Sandbox template: $IMAGE"
```

Make executable:

```bash
chmod +x bin/claude-sbx-rebuild
```

- [ ] **Step 6: Load the template**

Run:

```bash
./bin/claude-sbx-rebuild
sbx template ls
```

Expected: `claude-sbx:local` appears in the SBX template store.

- [ ] **Step 7: Commit**

```bash
git add Dockerfile bin/claude-sbx-rebuild
git commit -m "feat: add private claude sandbox template"
```

---

### Task 4: Docker SBX mixin kit and Claude worktree instructions

**Files:**
- Create: `kit/spec.yaml`

**Interfaces:**
- Consumes: built-in `claude` agent plus `claude-sbx:local` template supplied by the wrapper.
- Produces: kit memory instructions and egress allowances for plugin/bootstrap/runtime services.

- [ ] **Step 1: Create schema-v2 mixin**

`kit/spec.yaml`:

```yaml
schemaVersion: "2"
kind: mixin
name: claude-sbx-private
version: "1.0.0"
displayName: Claude SBX Private
description: Private development defaults for Claude Code in Docker Sandboxes

requires:
  agent: claude

permissions:
  network:
    allow:
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

agentInstructions:
  content: |
    This sandbox directly mounts the host Git repository read/write.

    Worktree rules:
    - Use project-local `.worktrees/`.
    - Before creating a worktree, verify `.worktrees/` is ignored by Git.
    - Prefer the native worktree capability when available; otherwise use `git worktree`.
    - Never create a sibling worktree outside the mounted repository.
    - When switching into a worktree, activate that worktree path in Serena before semantic reads or edits.
    - When returning to the primary checkout, reactivate the primary checkout in Serena.

    Tooling rules:
    - Superpowers owns development workflow and verification.
    - Frontend Design owns frontend visual quality.
    - Context7 is preferred for current library/framework documentation.
    - Serena is preferred for semantic code navigation and symbol-aware edits.
    - Use Playwright CLI skills for browser/frontend validation when a runnable local frontend exists.
    - Use project-local package-manager and lint/test versions when the repository defines them.
    - Do not install Java, Maven, or Gradle into this sandbox.
```

- [ ] **Step 2: Validate the kit**

Run:

```bash
sbx kit validate ./kit
```

Expected: success with schema version 2.

- [ ] **Step 3: Inspect resolved kit data**

Run:

```bash
sbx kit inspect ./kit --json | jq .
```

Expected: `kind` is `mixin`, `requires.agent` is `claude`, and the network allow list is present.

- [ ] **Step 4: Commit**

```bash
git add kit/spec.yaml
git commit -m "feat: add claude sbx mixin kit"
```

---

### Task 5: Idempotent Claude plugin and Playwright bootstrap

**Files:**
- Create: `scripts/bootstrap-claude.sh`
- Modify: `tests/test_bootstrap_helpers.sh`

**Interfaces:**
- Produces:
  - Superpowers plugin
  - Frontend Design plugin
  - Context7 plugin
  - Serena plugin
  - Caveman plugin
  - Playwright CLI skills
- Function `plugin_is_installed <plugin-id> <plugin-list-text>` is reusable by tests.

- [ ] **Step 1: Implement helper and safe source behavior**

`scripts/bootstrap-claude.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

plugin_is_installed() {
  local plugin="$1"
  local list_text="$2"
  grep -Fq "$plugin" <<<"$list_text"
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

plugin_list="$(claude plugin list 2>/dev/null || true)"

install_official() {
  local plugin="$1"

  if plugin_is_installed "$plugin" "$plugin_list"; then
    echo "already installed: $plugin"
    return
  fi

  claude plugin install "$plugin"
  plugin_list="${plugin_list}"$'\n'"${plugin}"
}

install_official "superpowers@claude-plugins-official"
install_official "frontend-design@claude-plugins-official"
install_official "context7@claude-plugins-official"
install_official "serena@claude-plugins-official"

if ! plugin_is_installed "caveman@caveman" "$plugin_list"; then
  claude plugin marketplace add JuliusBrussee/caveman
  claude plugin install caveman@caveman
fi

playwright-cli install --skills

mkdir -p "$HOME/.cache/claude-sbx"
touch "$HOME/.cache/claude-sbx/bootstrap-v1"
```

Make executable:

```bash
chmod +x scripts/bootstrap-claude.sh
```

- [ ] **Step 2: Run bootstrap helper tests**

Run:

```bash
bash tests/test_bootstrap_helpers.sh
```

Expected: PASS.

- [ ] **Step 3: Add a regression check that the script does not invoke Caveman's standalone installer**

Append to `tests/test_bootstrap_helpers.sh`:

```bash
if grep -Eq 'install\.sh|bin/install\.js|npx .*JuliusBrussee/caveman' "$ROOT/scripts/bootstrap-claude.sh"; then
  echo "bootstrap must use the Caveman plugin path only" >&2
  exit 1
fi
```

Run:

```bash
bash tests/test_bootstrap_helpers.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/bootstrap-claude.sh tests/test_bootstrap_helpers.sh
git commit -m "feat: bootstrap claude plugins and playwright skills"
```

---

### Task 6: Sandbox lifecycle wrapper

**Files:**
- Modify: `bin/claude-sbx`
- Test: `tests/test_name.sh`
- Test: `tests/test_worktree_guard.sh`

**Interfaces:**
- Consumes:
  - current Git repo
  - template `claude-sbx:local`
  - kit at `kit/`
  - bootstrap script mounted through the repo
- Produces:
  - one deterministic sandbox per repo
  - first-run creation + bootstrap
  - later reattachment without recreating the sandbox

- [ ] **Step 1: Add static configuration near the top of `bin/claude-sbx`**

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="claude-sbx:local"
KIT="$ROOT/kit"
BOOTSTRAP="$ROOT/scripts/bootstrap-claude.sh"
```

- [ ] **Step 2: Add sandbox existence helper**

```bash
sandbox_exists() {
  local name="$1"
  sbx ls -q | grep -Fxq "$name"
}
```

- [ ] **Step 3: Replace the executable bottom block with lifecycle logic**

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if ! repo_root="$(repo_root_from_cwd 2>/dev/null)"; then
    echo "claude-sbx: run this command from inside a Git repository" >&2
    exit 2
  fi

  if ! ensure_worktrees_ignored "$repo_root"; then
    cat >&2 <<'EOF'
claude-sbx: .worktrees/ is not ignored by Git.

Add this line to the repository's .gitignore:

.worktrees/

Then run claude-sbx again.
EOF
    exit 3
  fi

  name="$(sandbox_name_for_repo "$repo_root")"

  if ! sbx template ls | grep -Fq "$TEMPLATE"; then
    cat >&2 <<EOF
claude-sbx: template '$TEMPLATE' is not loaded.
Run:
  $ROOT/bin/claude-sbx-rebuild
EOF
    exit 4
  fi

  if sandbox_exists "$name"; then
    exec sbx run claude --name "$name"
  fi

  sbx create \
    --name "$name" \
    --template "$TEMPLATE" \
    --kit "$KIT" \
    claude \
    "$repo_root"

  sbx exec "$name" bash "$BOOTSTRAP"

  exec sbx run claude --name "$name"
fi
```

- [ ] **Step 4: Re-run host tests**

Run:

```bash
make test
```

Expected: PASS.

- [ ] **Step 5: Test first-run lifecycle against a disposable Git repo**

Run:

```bash
tmp="$(mktemp -d)"
git -C "$tmp" init -q
printf '.worktrees/\n' > "$tmp/.gitignore"

cd "$tmp"
/absolute/path/to/claude-sbx/bin/claude-sbx
```

Expected:
- a sandbox named `claude-<repo>-<8hex>` is created,
- the kit is applied only at creation,
- bootstrap runs,
- Claude attaches.

Exit Claude, then run the same command again.

Expected:
- no new sandbox is created,
- no `--kit` error occurs,
- the existing sandbox is reattached.

- [ ] **Step 6: Commit**

```bash
git add bin/claude-sbx
git commit -m "feat: add claude sandbox lifecycle wrapper"
```

---

### Task 7: In-sandbox verification script

**Files:**
- Create: `scripts/verify.sh`

**Interfaces:**
- Consumes: a running sandbox environment.
- Produces: exit code `0` only if required tools/plugins are present and Java tooling is absent.

- [ ] **Step 1: Create verification script**

`scripts/verify.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

required_commands=(
  claude
  git
  gh
  curl
  wget
  ssh
  rg
  fd
  jq
  yq
  fzf
  make
  just
  shellcheck
  shfmt
  docker
  node
  npm
  corepack
  pnpm
  python3
  uv
  go
  gopls
  goimports
  golangci-lint
  staticcheck
  govulncheck
  dlv
  playwright-cli
  psql
  sqlite3
  redis-cli
)

for cmd in "${required_commands[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing command: $cmd" >&2
    exit 1
  fi
done

for forbidden in java mvn gradle; do
  if command -v "$forbidden" >/dev/null 2>&1; then
    echo "forbidden Java tool present: $forbidden" >&2
    exit 1
  fi
done

node_version="$(node --version)"
[[ "$node_version" == "v24.19.0" ]] || {
  echo "unexpected Node version: $node_version" >&2
  exit 1
}

go_version="$(go version)"
grep -Fq "go1.26.6" <<<"$go_version" || {
  echo "unexpected Go version: $go_version" >&2
  exit 1
}

docker compose version >/dev/null

plugins="$(claude plugin list)"
for plugin in \
  superpowers@claude-plugins-official \
  frontend-design@claude-plugins-official \
  context7@claude-plugins-official \
  serena@claude-plugins-official \
  caveman@caveman
do
  grep -Fq "$plugin" <<<"$plugins" || {
    echo "missing Claude plugin: $plugin" >&2
    exit 1
  }
done

echo "claude-sbx verification passed"
```

Make executable:

```bash
chmod +x scripts/verify.sh
```

- [ ] **Step 2: Verify inside an existing sandbox**

Determine sandbox name:

```bash
name="$(./bin/claude-sbx 2>/dev/null || true)"
```

Do not use the wrapper for automation because it attaches interactively. Instead obtain the deterministic name by sourcing it:

```bash
source ./bin/claude-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash "$repo_root/scripts/verify.sh"
```

Expected: `claude-sbx verification passed`.

- [ ] **Step 3: Verify Docker-in-Docker**

Run:

```bash
sbx exec "$name" bash -lc '
docker run --rm hello-world >/dev/null
docker compose version
'
```

Expected: PASS.

- [ ] **Step 4: Verify Context7 and Serena registration at Claude level**

Run:

```bash
sbx exec "$name" bash -lc 'claude plugin list'
```

Expected: both `context7@claude-plugins-official` and `serena@claude-plugins-official` are listed.

Start a Claude session and issue:

```text
Use Serena to activate the current project and report the project path.
Then use Context7 to resolve the library ID for React.
```

Expected:
- Serena reports the current mounted repo path,
- Context7 resolves React documentation.

- [ ] **Step 5: Verify Playwright skills**

Run:

```bash
sbx exec "$name" bash -lc '
playwright-cli --help >/dev/null
find "$HOME/.claude" -path "*playwright*" -type f | head
'
```

Then in Claude:

```text
Use the Playwright CLI skill to open https://example.com, verify the page title, take a screenshot, and close the session.
```

Expected: successful headless browser interaction.

- [ ] **Step 6: Commit**

```bash
git add scripts/verify.sh
git commit -m "test: add sandbox verification script"
```

---

### Task 8: Worktree + JetBrains integration acceptance test

**Files:**
- Modify: `docs/usage.md`
- Modify: `README.md`

**Interfaces:**
- Proves that Claude-created worktrees inside `.worktrees/` are visible on macOS and usable by JetBrains.
- Documents the expected daily workflow.

- [ ] **Step 1: Run a real worktree acceptance test**

From a disposable or safe test repository:

```bash
printf '.worktrees/\n' >> .gitignore
git add .gitignore
git commit -m "chore: ignore local worktrees"
claude-sbx
```

Ask Claude:

```text
Using Superpowers, create an isolated worktree for branch sbx-worktree-test under .worktrees/, create a file named sbx-worktree-proof.txt containing "visible-from-host", and show the active worktree path.
```

Expected on the host:

```bash
cat .worktrees/sbx-worktree-test/sbx-worktree-proof.txt
```

Output:

```text
visible-from-host
```

Also run:

```bash
git worktree list
```

Expected: the worktree is listed under the host repository.

- [ ] **Step 2: Verify JetBrains visibility**

Open:

```bash
idea .worktrees/sbx-worktree-test
```

or the corresponding `goland` / `webstorm` launcher.

Expected:
- the file is immediately visible,
- edits made by Claude inside the worktree appear in the IDE without copying or syncing.

- [ ] **Step 3: Verify Serena follows worktree changes**

Inside Claude while located in `.worktrees/sbx-worktree-test`, ask:

```text
Activate the current worktree in Serena, then report the active project path and find sbx-worktree-proof.txt.
```

Expected: Serena reports the `.worktrees/sbx-worktree-test` path, not the primary checkout.

- [ ] **Step 4: Create `docs/usage.md`**

Document these exact daily commands:

```bash
# One-time build/load
~/dev/claude-sbx/bin/claude-sbx-rebuild

# In any Git repo
cd ~/dev/projects/example
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
claude-sbx

# Verify the repo sandbox
source ~/dev/claude-sbx/bin/claude-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash "$repo_root/scripts/verify.sh"

# Publish a dev server after sandbox creation
sbx ports "$name" --publish 3000:3000
```

Also document:
- direct mount means Claude can modify/delete anything in the selected repository,
- host files outside mounted workspaces are not part of the workspace,
- existing sandboxes keep their old image; remove/recreate a repo sandbox after rebuilding when new toolchain changes are required,
- `frontend-design` can show version `unknown` without being broken,
- Caveman is intentionally plugin-only,
- if a bootstrap download is blocked, inspect `sbx policy log <sandbox-name>`.

- [ ] **Step 5: Create concise `README.md`**

Include:
1. What the project does.
2. Requirements: Docker Desktop + Docker Sandboxes.
3. One-time setup.
4. `claude-sbx` daily command.
5. Toolchain summary.
6. Security model summary.
7. Link to `docs/usage.md`.

- [ ] **Step 6: Run final checks**

Run:

```bash
make test
sbx kit validate ./kit
shellcheck bin/claude-sbx bin/claude-sbx-rebuild scripts/bootstrap-claude.sh scripts/verify.sh tests/*.sh
```

Then run inside the sandbox:

```bash
sbx exec "$name" bash "$repo_root/scripts/verify.sh"
```

Expected: every command exits `0`.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/usage.md
git commit -m "docs: document claude sandbox workflow"
```

---

### Task 9: Installation into the host PATH

**Files:**
- Modify: `docs/usage.md`
- No repository code changes required unless a convenience installer is later justified.

**Interfaces:**
- Produces a host command `claude-sbx` callable from any Git repository.

- [ ] **Step 1: Create a user-local symlink**

Run on macOS:

```bash
mkdir -p "$HOME/.local/bin"
ln -sfn "$HOME/dev/claude-sbx/bin/claude-sbx" "$HOME/.local/bin/claude-sbx"
ln -sfn "$HOME/dev/claude-sbx/bin/claude-sbx-rebuild" "$HOME/.local/bin/claude-sbx-rebuild"
```

- [ ] **Step 2: Ensure `~/.local/bin` is on PATH**

For zsh, add only if absent:

```bash
grep -q 'HOME/.local/bin' "$HOME/.zshrc" \
  || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
```

Reload:

```bash
source "$HOME/.zshrc"
```

- [ ] **Step 3: Verify from an unrelated repository**

Run:

```bash
cd ~/dev/projects/any-git-repo
command -v claude-sbx
claude-sbx
```

Expected: the wrapper resolves this repository and attaches to its own deterministic sandbox.

- [ ] **Step 4: Record the host installation commands in `docs/usage.md` and commit**

```bash
git add docs/usage.md
git commit -m "docs: add host installation instructions"
```

---

## Final verification checklist

Run all of the following before declaring the implementation complete:

```bash
make test
sbx kit validate ./kit
./bin/claude-sbx-rebuild
```

From a test repository with `.worktrees/` ignored:

```bash
claude-sbx
```

Then verify:

```bash
source ~/dev/claude-sbx/bin/claude-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"

sbx exec "$name" bash "$repo_root/scripts/verify.sh"
sbx exec "$name" docker run --rm hello-world
```

Acceptance requires all of the following:

- Host repository edits made by Claude appear immediately in IntelliJ/GoLand/WebStorm.
- `.worktrees/<branch>` created in the sandbox appears on macOS and in `git worktree list`.
- Serena can activate the main checkout and then the worktree path.
- Context7 resolves current documentation.
- Playwright CLI can launch Chromium headlessly and take a screenshot.
- Superpowers, Frontend Design, Caveman, Context7, and Serena are available in Claude.
- Docker Engine and Docker Compose work inside the sandbox.
- Node is exactly `24.19.0`.
- Go is exactly `1.26.6`.
- Java, Maven, and Gradle are absent.

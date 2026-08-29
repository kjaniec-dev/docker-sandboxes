# Claude SBX — design

Date: 2026-08-21

## Goal

Provide one reusable Docker Sandbox setup for Claude Code on a private Mac that works with arbitrary Git repositories while keeping edits immediately visible to JetBrains IDEs.

## Workspace model

- Use Docker Sandboxes **direct mode** (default), not `--clone`.
- The selected repository is mounted read/write at the same absolute path inside the sandbox.
- Changes made by Claude are therefore visible immediately on the host and in IntelliJ / GoLand / WebStorm.
- Only the selected workspace is intentionally exposed read/write; the rest of the host remains outside the workspace mount.

## Worktrees

- Superpowers uses project-local `.worktrees/`.
- `.worktrees/` must be ignored by Git before worktrees are created.
- Worktrees remain inside the mounted repo tree, so both Claude and the host IDE can access them.
- Do not launch the sandbox with an external sibling worktree as the only mounted workspace.

## Toolchain

Included:

### Core CLI

- Git
- GitHub CLI (`gh`)
- Git LFS (`git-lfs`)
- curl
- wget
- CA certificates
- OpenSSH client
- ripgrep (`rg`)
- fd
- jq
- yq
- fzf
- make
- just
- unzip / zip / tar
- tree
- shellcheck
- shfmt

### Containers

- Docker Engine inside the sandbox
- Docker CLI
- Docker Compose

### Node / frontend

- Node.js
- npm
- Corepack
- pnpm
- Playwright CLI
- Chromium / Playwright runtime dependencies

Project-local versions of TypeScript, ESLint, Prettier, Next.js, Vite and similar frontend tooling remain authoritative; do not install global copies unless a repo explicitly requires them.

### Go

- Go
- gopls
- goimports
- golangci-lint
- staticcheck
- govulncheck
- Delve (`dlv`)

`gofmt`, `go vet` and `go test` come from the Go toolchain.

### Python

- Python 3
- uv

Prefer project-local Python environments and `uv` / `uvx` instead of globally installing repo-specific Python tooling.

### Database clients

- PostgreSQL client (`psql`)
- SQLite (`sqlite3`)
- Redis CLI (`redis-cli`)

Database servers are not installed globally; run PostgreSQL, Redis and other services through Docker when required.

### Tooling intentionally kept project-local or on-demand

Do not globally pin repo-specific application tooling such as TypeScript, ESLint, Prettier, Next.js, Vite, pytest or Ruff when the repository already defines its own versions. Prefer project-local commands (`pnpm exec`, package scripts, `uv run`) or ephemeral execution (`uvx`).

Cloud/infrastructure CLIs such as Terraform/OpenTofu, kubectl, Helm, gcloud, AWS CLI, Azure CLI, Wrangler and cloudflared are **not part of the base image**. Add them later through repo-aware bootstrap/detection only when a project actually needs them, keeping the universal sandbox lean.

Explicitly excluded:

- Java
- Maven
- Gradle

## Claude extensions

### Superpowers

Install from Anthropic's official Claude plugin marketplace:

`superpowers@claude-plugins-official`

Purpose: planning, TDD, debugging, worktrees, verification and execution workflows.

### Caveman

Install as a Claude Code plugin from the Caveman marketplace.

Purpose: reduce verbose output while retaining technical substance.

Do not install a second standalone hook layer in addition to the plugin hooks.

### Frontend Design (Anthropic)

Install Anthropic's official `frontend-design` Claude Code plugin/skill.

Purpose: improve UI implementation quality by giving Claude explicit frontend design guidance for visual hierarchy, typography, spacing, layout, motion and avoiding generic AI-looking interfaces.

Behavior:

- Keep it available globally in the sandbox for frontend-capable repositories.
- Allow automatic skill invocation when Claude is implementing or redesigning UI.
- It complements rather than replaces Superpowers: Superpowers owns the development process; Frontend Design owns frontend design quality.
- Pair frontend implementation with Playwright validation when the application can be run locally.

### Context7

Install the Context7 Claude Code plugin.

Purpose: current library/framework documentation, skills and docs research.

`CONTEXT7_API_KEY` is optional; anonymous mode remains supported.

### Serena

Use Serena as an MCP server, installed with `uv`/`uvx`.

Important worktree rule: do not permanently pin Serena to the primary checkout at Claude startup.

Start Serena with a configuration that exposes project activation (`query-projects` mode). Claude instructions will require:

1. Activate the current Git repo when a session begins.
2. After Superpowers creates or enters a worktree, activate that worktree path in Serena before semantic reads or edits.
3. Verify Serena's active project when switching workspaces.

This prevents semantic edits from accidentally targeting the primary checkout while shell commands are running in a worktree.

### Playwright

Use `@playwright/cli` plus its installed Claude skills rather than Playwright MCP by default.

Purpose: frontend navigation, screenshots, browser assertions and exploratory checks with lower context overhead.

## Docker customization strategy

Use three layers:

1. **Custom template image** based on `docker/sandbox-templates:claude-code-docker`. Docker documents no combined `claude-code-minimal-docker` variant. We therefore keep the supported Docker-enabled Claude base, explicitly purge Java/Maven/Gradle, and pin/overwrite the Node and Go runtimes we want.
2. **Docker SBX kit** for agent instructions, network permissions and non-managed runtime configuration.
3. **Post-create bootstrap** through `sbx exec` for Claude Code plugins/MCP registration that must write to Claude-managed user configuration.

Reason: Docker recreates Claude's managed user configuration files when a sandbox is created and explicitly reserves `~/.claude.json` / `~/.claude/settings.json`. We therefore do not bake or statically overwrite those files.

## Claude behavior

- Keep Docker Sandbox's default `--dangerously-skip-permissions` behavior.
- Claude may freely modify files inside the mounted repository.
- Superpowers remains the process/workflow layer.
- Frontend Design is the UI design/implementation-quality layer.
- Serena is the semantic code navigation/edit layer.
- Context7 is the current documentation layer.
- Playwright is the browser/frontend validation layer.
- Caveman controls response verbosity.

## Repository compatibility

The wrapper should work from any Git repository by running a single command from the repo root, e.g.:

`claude-sbx`

The wrapper will:

1. Resolve the Git repository root.
2. Verify `.worktrees/` is ignored or warn clearly.
3. Create/reuse a deterministic sandbox name for the repo.
4. If this sandbox is new, run an idempotent `sbx exec` bootstrap that installs/configures Claude extensions.
5. Start Claude using the custom template + kit in direct mode.
6. Publish commonly used development ports when configured.

## Planned project structure

```text
claude-sbx/
├── Dockerfile
├── kit/
│   ├── spec.yaml
│   └── files/
├── bin/
│   ├── claude-sbx
│   └── claude-sbx-rebuild
├── scripts/
│   ├── bootstrap-claude.sh
│   ├── configure-serena.sh
│   └── verify.sh
├── docs/
│   └── usage.md
└── README.md
```

## Acceptance criteria

- `claude-sbx` launched from a Git repo starts Claude Code in a Docker Sandbox.
- Host IDE sees file edits immediately.
- Claude can run Docker workloads inside the sandbox.
- Node/npm/Corepack/pnpm, Go tooling, Python/uv, Docker Compose, Git LFS, core Unix CLI tools and DB clients are available; Java tooling is absent.
- Superpowers, Frontend Design, Caveman and Context7 are installed idempotently after sandbox creation and available to Claude.
- Serena can be activated for the main checkout and switched to a worktree.
- Playwright CLI and skills are usable for frontend validation.
- A Superpowers-created `.worktrees/<branch>` directory is visible from macOS and can be opened in JetBrains.
- Verification script checks the installed tools and integrations.

# Multi-Harness Docker Sandbox Design

Date: 2026-08-26

## Goal

Evolve this repository from a Claude Code-specific Docker Sandbox setup into a public, extensible multi-harness project. The first supported harnesses are Claude Code and Codex; Antigravity CLI and OpenCode remain future additions.

## Scope

This change covers:

- extracting the existing Claude Code setup into a harness-specific directory;
- adding a separate Codex harness with its own wrapper, template, kit and bootstrap lifecycle;
- sharing the development toolchain and sandbox conventions between harnesses;
- preserving `claude-sbx` as a backwards-compatible command;
- making documentation and configuration suitable for a public GitHub repository;
- adding tests for shared behavior and harness-specific lifecycle behavior.

This change does not install or implement Antigravity CLI or OpenCode.

## Repository architecture

```text
claude-sbx/
├── shared/
│   ├── install-system-toolchain.sh    # shared root-owned toolchain installer
│   └── install-user-toolchain.sh      # shared agent-owned toolchain installer
├── harnesses/
│   ├── claude-code/
│   │   ├── Dockerfile
│   │   ├── kit/spec.yaml
│   │   ├── bin/claude-code-sbx
│   │   └── scripts/{bootstrap,verify}.sh
│   └── codex/
│       ├── Dockerfile
│       ├── kit/spec.yaml
│       ├── bin/codex-sbx
│       └── scripts/{bootstrap,verify}.sh
├── bin/
│   ├── claude-sbx                     # compatibility wrapper
│   └── codex-sbx                      # public Codex entrypoint
├── tests/                             # host-side shell tests
├── docs/usage.md                      # common usage and public requirements
└── README.md
```

The exact placement of a shared Dockerfile layer may be simplified if Docker Sandbox template inheritance cannot consume it directly. The externally visible boundary remains the same: each harness owns a Dockerfile/template tag, while common toolchain instructions have one source of truth wherever Docker permits.

The Claude Dockerfile extends `docker/sandbox-templates:claude-code-docker`; the Codex Dockerfile extends `docker/sandbox-templates:codex-docker`. These agent-matched Docker Engine variants provide the full engine and Docker Compose inside each sandbox.

## Harness lifecycle

Claude Code keeps its existing behavior:

- command: `claude-sbx`;
- implementation: `harnesses/claude-code/bin/claude-code-sbx`;
- sandbox name: `claude-<repo-slug>-<8-hex-path-digest>`;
- template: `claude-sbx:local`;
- bootstrap: Claude marketplace plugins and Playwright skills;
- verification: Claude CLI, plugins, toolchain and pinned runtime checks.

Codex follows the same direct-mount lifecycle:

- command: `codex-sbx`;
- sandbox name: `codex-<repo-slug>-<8-hex-path-digest>`;
- template: `codex-sbx:local`;
- bootstrap: Codex-specific setup only, without Claude plugin state;
- verification: Codex CLI plus the shared toolchain and sandbox invariants.

Each harness has an independent sandbox and independent agent-managed configuration. The target Git repository is mounted read/write at the same absolute path. The infrastructure repository is mounted read-only when the target repository is different from it.

## Shared toolchain

Both harnesses expose the current full development toolchain:

- Docker Engine and Docker Compose;
- Git, GitHub CLI, Git LFS and common shell utilities;
- Node.js 24.19.0, npm, Corepack and pnpm;
- Go 1.26.6 and the existing Go tools;
- Python 3 and uv;
- OpenJDK 25, Maven and Gradle;
- PostgreSQL, SQLite and Redis clients;
- Playwright CLI and Chromium dependencies.

Repository-local versions remain authoritative for project-specific tools. No credentials, API keys or agent session files are baked into images or committed to the repository.

## Public repository requirements

- Remove private-machine wording from public-facing documentation.
- Describe macOS, Docker Desktop with Docker Sandboxes, and Git as the host requirements.
- Keep authentication interactive or sandbox-managed for each harness.
- Exclude generated images, exports, local configuration, caches, IDE state and secrets from Git.
- Keep `.worktrees/` as a project-local, Git-ignored directory.

## Compatibility and migration

The current Claude command remains usable without changing its user-facing invocation. Its root wrapper delegates to the harness implementation. Existing tests and docs are updated to target the new paths while retaining coverage for the compatibility command.

The migration must not silently reuse Claude's sandbox or configuration for Codex. Template names, sandbox names, bootstrap scripts and verification commands remain harness-specific.

## Testing

Host-side tests must cover:

- deterministic Claude and Codex sandbox naming;
- slug generation and path digest behavior;
- `.worktrees/` ignore guard;
- wrapper sourcing without side effects;
- correct template, kit, bootstrap and command wiring;
- compatibility delegation from `bin/claude-sbx`;
- shared toolchain/version assertions where practical.

Sandbox verification remains an explicit smoke test run inside a created sandbox. It must report which harness failed and must not require host-only agent binaries.

## Acceptance criteria

1. `claude-sbx` still launches Claude Code with the existing direct-mount behavior.
2. `codex-sbx` launches Codex in a separate deterministic sandbox.
3. Claude and Codex never share agent-managed configuration or sandbox identity.
4. Both harnesses expose the same full development toolchain.
5. Shared infrastructure has one maintainable source of truth where the Docker build system allows it.
6. Public documentation contains no private credentials or machine-specific assumptions.
7. `make test` passes on the host.
8. Each harness has an inside-sandbox verification path.
9. The structure allows future `harnesses/antigravity/` and `harnesses/opencode/` additions without changing the shared contract.

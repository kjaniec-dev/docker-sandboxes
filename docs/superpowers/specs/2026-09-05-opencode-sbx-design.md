# OpenCode Docker Sandbox Design

Date: 2026-09-05

## Goal

Add OpenCode as a first-class Docker Sandbox harness with the same isolated,
direct-mount workflow and development toolchain currently provided by Claude
Code and Codex.

## Scope

This change covers:

- a dedicated OpenCode image, kit, launcher, rebuild command, bootstrap, and
  verification script;
- independent OpenCode template and sandbox naming;
- OpenCode MCP configuration for Serena and Context7;
- global discovery of Superpowers, Caveman, and Playwright skills;
- host-side lifecycle, layout, wiring, and documentation coverage;
- provider authentication documentation using Docker Sandbox secrets.

This change does not:

- install or persist provider API keys in the image or repository;
- replace the official OpenCode runtime;
- change Claude Code or Codex behavior;
- add Antigravity or other agent harnesses.

## Architecture

OpenCode owns `harnesses/opencode/` with these files:

- `Dockerfile`, extending `docker/sandbox-templates:opencode-docker`;
- `kit/spec.yaml`, requiring the `opencode` agent and declaring its network
  policy and agent instructions;
- `bin/opencode-sbx`, implementing direct-mount lifecycle and deterministic
  naming;
- `scripts/bootstrap.sh`, configuring OpenCode and installing agent skills;
- `scripts/verify.sh`, checking the agent, toolchain, configuration, and
  skills.

The Dockerfile uses the existing shared system and user toolchain installers
and keeps Node `24.19.0`, Go `1.26.6`, and OpenJDK `25` assertions aligned with
the other harnesses.

Root integration adds:

- `bin/opencode-sbx` compatibility/public delegate;
- `bin/opencode-sbx-rebuild` template build/load delegate;
- `make rebuild-opencode` and `make verify-opencode`;
- OpenCode entries in README, usage documentation, and host tests.

OpenCode uses template tag `opencode-sbx:local` and sandbox names of the form
`opencode-<repo-slug>-<8-hex-path-digest>`. It never reuses Claude or Codex
configuration, template, or sandbox identity.

## Runtime Flow

1. The root wrapper resolves symlinks and delegates to the harness launcher.
2. The launcher rejects repositories where `.worktrees/` is not ignored.
3. It creates or reattaches to the deterministic OpenCode sandbox, mounting the
   target repository read/write and this harness repository read-only when they
   differ.
4. On creation, the kit runs the OpenCode bootstrap through `sbx exec`.
5. The launcher starts OpenCode with `sbx run --name <name>` and forwards args.
6. Rebuild exports the local image, removes a matching loaded template, and
   loads the new tar into Docker Sandboxes.

## Bootstrap

Bootstrap remains idempotent and refuses to replace unexpected non-git state.
It will:

- create or update global OpenCode configuration under
  `~/.config/opencode/` without storing credentials;
- configure enabled Serena local MCP using the installed `serena` executable;
- configure enabled Context7 remote MCP at
  `https://mcp.context7.com/mcp`;
- clone/update Superpowers and link it into `~/.agents/skills/`;
- verify the pinned Caveman checkout and link its skill into
  `~/.agents/skills/`;
- install Playwright CLI skills for agent-compatible discovery;
- write an idempotence marker under `~/.cache/claude-sbx/`; reattach runs
  bootstrap again when this marker is missing.

OpenCode discovers skills from global `~/.agents/skills/`, so the linked skills
are available without modifying target repositories. Existing user config must
be preserved; managed MCP entries are additive and deterministic. If a higher-
precedence `opencode.jsonc` defines conflicting `serena` or `context7` entries,
bootstrap fails before writing managed `config.json`.

## Security and Network

Authentication remains host-side and sandbox-managed. Documentation covers
`sbx secret set openai`, `anthropic`, `google`, `xai`, `groq`, and `openrouter`,
plus the custom OpenCode Zen secret flow where needed. No secret
is copied into Dockerfiles, kits, bootstrap scripts, generated images, or Git.

The OpenCode kit allowlist includes domains required by the shared toolchain,
GitHub-hosted bootstrap sources, Context7, OpenCode Zen, and documented provider
endpoints. It follows least privilege and is extended only when an actual
bootstrap or provider failure identifies a missing domain.

## Verification

Host tests cover:

- executable layout and official OpenCode base image wiring;
- source-safe root and harness wrappers;
- deterministic slug and path-digest naming;
- `.worktrees/` guard and direct workspace mounts;
- `sbx create`, bootstrap, and `sbx run` lifecycle arguments;
- Makefile, README, usage, template, kit, and command wiring.

Inside-sandbox verification checks:

- `opencode` and all shared required commands;
- Node `v24.19.0`, Go `1.26.6`, Java/Javac `25`, Maven, Gradle, and Docker
  Compose;
- Serena and Context7 entries in resolved OpenCode configuration;
- Superpowers, Caveman, and Playwright skill files.

The completion gate is `make test`. If Docker Sandboxes is available, rebuild
the OpenCode template, remove the existing OpenCode sandbox, recreate it, and
run its verification script with `sbx exec`.

## Acceptance Criteria

1. `opencode-sbx` starts OpenCode in its own deterministic sandbox.
2. OpenCode never shares agent-managed configuration or identity with Claude
   Code or Codex.
3. OpenCode exposes the shared pinned development toolchain.
4. Serena, Context7, Superpowers, Caveman, and Playwright are available after
   bootstrap.
5. Existing user OpenCode config is preserved while managed MCP entries are
   present.
6. No credentials or machine-specific paths enter tracked files or images.
7. `make test` passes on the host.
8. Inside-sandbox verification reports OpenCode-specific failures clearly.

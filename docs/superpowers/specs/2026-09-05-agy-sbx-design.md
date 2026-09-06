# Antigravity CLI Docker Sandbox Design

Date: 2026-09-05

## Goal

Add Antigravity CLI (Google's `agy`) as a first-class Docker Sandbox harness
with the same isolated, direct-mount workflow and development toolchain
currently provided by Claude Code, Codex, and OpenCode.

## Scope

This change covers:

- a dedicated Antigravity image, kit, launcher, rebuild command, bootstrap, and
  verification script;
- independent Antigravity template and sandbox naming;
- Antigravity MCP configuration for Serena and Context7;
- global discovery of Superpowers, Caveman, and Playwright skills;
- host-side lifecycle, layout, wiring, and documentation coverage;
- authentication documentation covering Google Sign-In and `GEMINI_API_KEY`.

This change does not:

- install or persist Google credentials or API keys in the image or repository;
- replace or wrap the official Antigravity runtime (the image pins a version;
  `agy update` inside a sandbox remains possible but does not survive
  recreation, and rebuild is the supported upgrade path);
- change Claude Code, Codex, or OpenCode behavior.

## Architecture

Antigravity owns `harnesses/antigravity-cli/` with these files:

- `Dockerfile`, extending `docker/sandbox-templates:shell-docker` (the neutral
  Docker Sandboxes base: Ubuntu 26.04, `agent` user, Docker-in-Docker); no
  official Antigravity agent template exists;
- `kit/spec.yaml`, declaring its network policy and agent instructions;
- `bin/agy-sbx`, implementing direct-mount lifecycle and deterministic
  naming;
- `scripts/bootstrap.sh`, configuring Antigravity MCP and installing agent
  skills;
- `scripts/verify.sh`, checking the agent, toolchain, configuration, and
  skills.

The Dockerfile installs Antigravity CLI deterministically before the shared
toolchain installers:

- pinned release `1.1.27-5211191891591168` from
  `https://storage.googleapis.com/antigravity-public/antigravity-cli/`;
- architecture selected from `TARGETARCH`: `linux-x64/cli_linux_x64.tar.gz`
  (sha256 `f874d4f6b8a73c2df660f580f25fb656fcb6e64adbfd746e6692e837fd9a20be`)
  or `linux-arm/cli_linux_arm64.tar.gz` (sha256
  `97fc9fe5a6067406cd02cbe4ae6e362c9623a24d33bec486911246c17ceb6a94`);
- sha256 verified before extraction; the `antigravity` binary is installed as
  `/usr/local/bin/agy`.

The Dockerfile then uses the existing shared system and user toolchain
installers and keeps Node `24.19.0`, Go `1.26.6`, and OpenJDK `25` assertions
aligned with the other harnesses.

Root integration adds:

- `bin/agy-sbx` compatibility/public delegate;
- `bin/agy-sbx-rebuild` template build/load delegate;
- `make rebuild-agy` and `make verify-agy`;
- Antigravity entries in README, usage documentation, and host tests.

Antigravity uses template tag `agy-sbx:local` and sandbox names of the
form `agy-<repo-slug>-<8-hex-path-digest>`. It never reuses Claude,
Codex, or OpenCode configuration, template, or sandbox identity.

### Agent registration

Resolved at host integration (2026-09-06): Docker Sandboxes rejects
`antigravity` as an agent name (`ERROR: unknown agent "antigravity"`). The
harness therefore uses the generic `shell` agent registration and launches the
installed `agy` binary through the documented interactive exec path:
`sbx exec -it <name> agy "$@"`. The harness name, template tag, sandbox
prefix, command wrappers, and runtime remain Antigravity-specific; only the
Docker Sandboxes agent registration is `shell`.

## Runtime Flow

1. The root wrapper resolves symlinks and delegates to the harness launcher.
2. The launcher rejects repositories where `.worktrees/` is not ignored.
3. It creates or reattaches to the deterministic Antigravity sandbox, mounting
   the target repository read/write and this harness repository read-only when
   they differ.
4. On creation, the launcher runs the Antigravity bootstrap through
   `sbx exec`; reattach runs bootstrap again when the idempotence marker is
   missing.
5. The launcher starts Antigravity CLI with `sbx run --name <name>` and
   forwards args.
6. Rebuild exports the local image, removes a matching loaded template, and
   loads the new tar into Docker Sandboxes.

## Bootstrap

Bootstrap remains idempotent and refuses to replace unexpected non-git state.
Antigravity discovers global skills at `~/.gemini/config/skills/<name>/` and
MCP servers in `~/.gemini/config/mcp_config.json`. Bootstrap will:

- ensure managed MCP entries in `~/.gemini/config/mcp_config.json`:
  `serena` (stdio, `serena start-mcp-server --context=ide-assistant
  --project-from-cwd`) and `context7` (http,
  `https://mcp.context7.com/mcp`); missing or matching entries are ensured
  with a managed `jq` merge that writes the exact entries `agy mcp add`
  produces; existing entries that conflict with the managed definitions fail
  bootstrap before any write, mirroring OpenCode managed-entry semantics;
- clone/update Superpowers and link each of its skills into
  `~/.gemini/config/skills/`;
- verify the pinned Caveman checkout (same tag and revision as the other
  harnesses) and link its skill into `~/.gemini/config/skills/`;
- install Playwright CLI skills globally and link them into
  `~/.gemini/config/skills/`;
- write an idempotence marker under `~/.cache/claude-sbx/`; reattach runs
  bootstrap again when this marker is missing.

Git checkouts live under `~/.gemini/` and only the skill links appear in the
discovery directory, so no skill content is written into mounted target
repositories.

## Security and Network

Authentication is not baked into the image.

The default flow is Google Sign-In: inside the sandbox `agy` detects the
headless environment and prints an authorization URL that the user completes
in a host browser. Tokens persist in sandbox state (file-backed storage, as
the container has no system keyring), are refreshed automatically, and survive
reattach; sign-in is required again only after `sbx rm` and recreation.

The alternative is an API key: `sbx secret set-custom` with environment
variable `GEMINI_API_KEY` scoped to `generativelanguage.googleapis.com`,
documented like the OpenCode Zen flow. No secret is copied into Dockerfiles,
kits, bootstrap scripts, generated images, or Git.

The Antigravity kit allowlist includes domains required by the shared
toolchain, GitHub-hosted bootstrap sources, Context7, and Antigravity runtime
needs: `storage.googleapis.com`, `accounts.google.com`,
`oauth2.googleapis.com`, `sts.googleapis.com`, `aicode.googleapis.com`,
`cloudcode-pa.googleapis.com`, `generativelanguage.googleapis.com`, and
`antigravity.google.com`. It follows least privilege and is extended only when
an actual bootstrap or runtime failure identifies a missing domain.

## Verification

Host tests cover:

- executable layout and the shell base image wiring;
- pinned Antigravity version, build id, and per-arch sha256 in the Dockerfile;
- source-safe root and harness wrappers;
- deterministic slug and path-digest naming;
- `.worktrees/` guard and direct workspace mounts;
- `sbx create`, bootstrap, and `sbx run` lifecycle arguments;
- Makefile, README, usage, template, kit, and command wiring.

Inside-sandbox verification checks:

- `agy --version` reports `1.1.27`, and all shared required commands exist;
- Node `v24.19.0`, Go `1.26.6`, Java/Javac `25`, Maven, Gradle, and Docker
  Compose;
- Serena and Context7 entries in `~/.gemini/config/mcp_config.json`;
- Superpowers, Caveman, and Playwright skill files under
  `~/.gemini/config/skills/`.

The completion gate is `make test`. If Docker Sandboxes is available, rebuild
the Antigravity template, remove the existing Antigravity sandbox, recreate
it, and run its verification script with `sbx exec`.

## Acceptance Criteria

1. `agy-sbx` starts Antigravity CLI in its own deterministic sandbox.
2. Antigravity never shares agent-managed configuration or identity with
   Claude Code, Codex, or OpenCode.
3. Antigravity exposes the shared pinned development toolchain.
4. Serena, Context7, Superpowers, Caveman, and Playwright are available after
   bootstrap.
5. Google Sign-In is documented as once per sandbox lifetime, with
   `GEMINI_API_KEY` as the documented alternative; no credentials enter
   tracked files or images.
6. `make test` passes on the host.
7. Inside-sandbox verification reports Antigravity-specific failures clearly.

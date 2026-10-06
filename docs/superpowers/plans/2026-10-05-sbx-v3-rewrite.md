# SBX V3 Rewrite Implementation Plan

> **Execution:** Use superpowers:executing-plans inline, as selected by the user. Preserve the completed behavior/native audits and RED test handoffs.

**Goal:** Execute `CODEX_REWRITE_PROMPT.md`, preserving required agent behavior in the supplied V3 architecture and deleting the legacy implementation after parity validation.

**Architecture:** Official V3 workloads or thin Claude/OpenCode workloads compose with official agent mixins, one local dev mixin, and declarative environments. One symlinked launcher delegates lifecycle to SBX. Serena alone uses a sandbox-local configuration adapter.

**Tech Stack:** SBX 0.46+, Sandbox Kit V3, Bash, standard-library Python, Docker kit builder.

**Spec:** `CODEX_REWRITE_PROMPT.md`, supplied target files and repository `AGENTS.md`.

## Global Constraints

- SBX minimum version: 0.46.0.
- Sandbox Kit schema: V3 only.
- Prefer official Docker V3 workloads and mixins.
- Preserve the client's already-working ADC/WIF mechanism; do not invent a new enterprise auth flow.
- Do not run Serena through `sbx mcp --command`; that would execute it on the host.
- No legacy/, old/, v2/, V2 kits, template tar handling, infrastructure mounts, per-agent rebuilds, or generic Bash framework.
- Preserve the user's staged target migration on `rewrite/sbx-v3-clean`; work in this checkout and leave changes reviewable without committing unrelated staged work.

## Review Focus

- A launch from a linked worktree stays within its mounted repository and rejects an unignored `.worktrees/`.
- Reuse after stop starts the same sandbox; deletion/recreation rebuilds current kits.
- Malformed agent configuration fails without destroying unrelated user data.
- Official hooks and local Serena setup do not duplicate remote MCP setup or erase existing configuration.
- Missing credentials and failed agent/browser/MCP checks must not produce a passing smoke result.

### Task 1: Validate and repair the native V3 composition

**Files:** `workloads/*`, `mixins/dev/*`, `env/*`, `mixins/vertex/*`.
**Interfaces:** Environments declare `SBX_AGENT_KIND`; the adapter registers local Serena using the supported CLI/config for each agent. Official kits own gateway and provider behavior.

- [x] Inventory legacy behaviors and compare installed SBX contracts before implementation.
- [x] Run `tests/validate.sh` and a native kit inspect/build; record actual schema/build failures before repair.
- [x] Repair unsupported V3 fields and recover required shared tooling and developer network policy in `mixins/dev`.
- [x] Exercise adapter behavior with standard-library tests for preservation, idempotence, malformed input, and all supported config formats before changing it.
- [x] Verify native builds and all seven environment plans.

### Task 2: Launcher and behavioral validation

**Files:** `bin/sbx-dev`, `tests/validate.sh`, `tests/test_behavior.py`.
**Interfaces:** Public symlinks invoke the same launcher, which performs `sbx env run` then `sbx run`; all agent arguments remain separate argv entries.

- [x] Write/run behavioral tests for profile matrix, naming, argv forwarding, path/symlink handling, ignored worktrees, failures, and SBX version floor.
- [x] Implement minimal launcher fixes supported by failing tests; preserve native environment approval and lifecycle.
- [x] Replace broad YAML/grep checks with behavior tests plus native kit validation and environment plans; fail required native verification when unavailable.
- [x] Run offline behavioral checks and native validation.

### Task 3: Runtime matrix and legacy removal

**Files:** `tests/smoke.sh`, `tests/smoke-check.py`, `docs/cutover.md`, `docs/client-vertex.md`, `README.md`, `.gitignore`, `.dockerignore`, obsolete `harnesses/`, `shared/`, commands, tests, and docs.
**Interfaces:** Smoke creates only uniquely named disposable environments, checks actual tooling, Chromium, agent startup, skills/context, Context7 gateway and Serena stdio, and tests stop/start plus delete/recreate.

- [x] Strengthen smoke checks so failures propagate; add opt-in credential-backed model probes and clearly separate portable validation from client-machine authentication.
- [x] Run Codex, Antigravity, Junie, Claude, OpenCode and client Copilot in the brief's order; Vertex runtime is deferred by the user.
- [x] Recover any available approved Vertex auth mechanism; record unavailable client evidence rather than inventing credentials or claiming validation.
- [x] After required parity evidence, delete obsolete implementation and stale documentation completely, retaining Git history as the archive.
- [x] Rerun behavioral/native validation and the runtime matrix; record concrete results and remaining external blockers in `docs/cutover.md`.
- [x] Perform an independent final review and fix consequential findings.

## Execution evidence

- Tasks 1 and 2: complete in the working tree; native validation passes 34 tests, four source kits and seven environment plans.
- Task 3: legacy removal and final review are complete. The Important malformed-MCP merge regression is fixed (RED→GREEN); native Antigravity/OpenCode fresh/restarted/recreated smoke passes. The complete final six-environment runtime matrix passed, including authenticated Claude/Codex requests at all three stages.
- Vertex runtime/ADC-WIF is deferred by the user's explicit instruction. Other missing/rejected provider credentials remain documented in docs/cutover.md.
- One Minor review suggestion remains deferred: a sandbox-local persistence marker in the lifecycle test.
- The existing staged migration is preserved. No commits, merges or pushes were made.

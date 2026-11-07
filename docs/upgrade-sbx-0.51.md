# Upgrade gate: Docker Sandboxes 0.51.0

- Upstream: [Docker Sandboxes v0.51.0](https://github.com/docker/sbx-releases/releases/tag/v0.51.0), released 2026-11-03.
- Baseline: `main` before this change required SBX 0.50.0+.
- New minimum: **0.51.0**. This is a security/compatibility floor, **not** proof the full agent matrix works at 0.51.0.
- The shared mixins and local workloads are already Kits v3; no template-v2 migration or unverified removal of adapters is included.

## Why update?

The release blocks `sbx cp` symlink escapes through mounted directories, verifies ownership of Unix daemon sockets, prevents Git filter execution during `sbx kit sign`, and prevents network-policy commands with an empty sandbox target from applying rules globally. It also switches built-in agent resolution to published `docker.io/sbx/<agent>:latest` kits, adds explicit destination-host requirements for custom secrets, and changes clipboard copy to opt-in.

This repository already specifies destination hosts for Junie and client Vertex secrets. Check *machine-local* secrets and overlays separately. Source-kit and pinned-official-kit changes are deliberately out of scope: a release note alone does not demonstrate that a workaround can be removed.

## Context7 conflict: reuse host registration

If `sbx env run` reports `MCP server "context7" is already registered with another definition`,
the updated `env/common.sbxenv.yaml` no longer declares a duplicate host-global MCP server.
The launcher instead calls `sbx mcp load context7 --sandbox <name>` after applying the
environment. This reuses the existing native registration and OAuth credentials; it does
not remove or register a different Context7 definition.

Run `sbx mcp inspect context7` to confirm the host registration. On a new host
with no registration, set it up once with `sbx mcp add context7 --url
https://mcp.context7.com/mcp` and authorize with `sbx mcp auth context7`
if prompted. Do **not** blindly run `sbx mcp rm context7`: that can affect
other sandboxes and stored authentication. Native `sbx mcp load` should be checked
for idempotent behavior with repeated launcher invocations during local validation.

## macOS preflight — owner-operated

**Run on a trusted host, not inside a project workspace exposed to an untrusted agent.** Back up any existing sandbox-local files or unpushed commits before recreating sandboxes. Existing sandboxes do not automatically receive new kit composition, pins, CA stores or all native lifecycle behavior.

1. Update the local SBX CLI and check both client and daemon:

   ```bash
   brew upgrade docker/tap/sbx
   sbx version --json
   sbx daemon restart
   ```

2. Confirm the resulting **client is at least 0.51.0**; inspect daemon/CLI compatibility and any pinned official kit resolution before running real workloads.
3. Inspect native secrets and policy configuration for explicit destination hosts. In particular, verify the client Claude Vertex scoped `ANTHROPIC_AUTH_TOKEN` host bindings and the Junie custom secret; never paste token values into PR comments or logs. On 0.51.0, unmapped custom-secret destination hosts are not substituted.
4. If the macOS runner/host is managed, obtain approval before any CLI update, daemon restart, policy changes, VM deletion or use of customer credentials. Work only on disposable sandbox names created by smoke scripts.

## Tests to run locally

From a **clean checkout of this PR** with supported `sbx`, Git, Python, the configured kit builder and required external kit references:

```bash
./tests/validate.sh
```

Then run the per-agent sandbox lifecycle test in an isolated environment. Each invocation creates a disposable Git repository and sandbox, verifies fresh/start-stop-restart/remove-recreate behavior and cleans up on success.

```bash
SBX_PROFILE=personal ./tests/smoke.sh claude
SBX_PROFILE=personal ./tests/smoke.sh codex
SBX_PROFILE=personal ./tests/smoke.sh opencode
SBX_PROFILE=personal ./tests/smoke.sh antigravity
SBX_PROFILE=personal ./tests/smoke.sh junie
SBX_PROFILE=client ./tests/smoke.sh copilot
SBX_PROFILE=client ./tests/smoke.sh claude
```

Client Claude requires a configured approved `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION` and a machine-local client overlay (see [client Vertex configuration](client-vertex.md)). If a profile is not available or authenticated, report **BLOCKED**, not PASS. Use the optional `SBX_SMOKE_MODEL=1` only for profiles with explicitly approved, working credentials and account balance. The default infrastructure smoke does **not** verify an authenticated model request. For example:

```bash
SBX_PROFILE=personal SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
SBX_PROFILE=client SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
```

The smoke checks include the available toolchain, native shared read-only skills, gateway Context7, local Serena, Git/worktree checks, lifecycle and agent-specific runtime probes. Review the test coverage and actual logs rather than inferring that every possible isolation escape is covered. Do **not** attempt to reproduce workspace/symlink security vulnerabilities against real host files.

## PR acceptance checklist

- [ ] GitHub-hosted offline validation (ShellCheck, Ruff, Python tests) passed on PR head SHA.
- [ ] Local macOS version and daemon preflight verified at 0.51.0+.
- [ ] Native `./tests/validate.sh` passed (five source-kit inspections plus seven environment plans).
- [ ] Personal Claude: fresh / restart / recreate — PASS.
- [ ] Personal Codex: fresh / restart / recreate — PASS.
- [ ] Personal OpenCode: fresh / restart / recreate — PASS.
- [ ] Personal Antigravity: fresh / restart / recreate — PASS.
- [ ] Personal Junie: fresh / restart / recreate — PASS.
- [ ] Client Copilot: fresh / restart / recreate — PASS.
- [ ] Client Claude Vertex: fresh / restart / recreate — PASS.
- [ ] Model requests (where approved): authenticated completion verified; record skipped profiles distinctly.
- [ ] All disposable sandboxes removed; logs checked for errors and secret leakage.
- [ ] Existing project sandboxes were not modified.

**Manual macOS smoke status: PENDING / NOT RUN** until the owner records the outcomes for the PR head SHA. Do not mark the PR ready for merge based only on offline GitHub Actions results.

## Rollback and recovery

If tests regress, **do not merge this PR**. Keep existing project sandboxes intact, record CLI version, agent/profile, failing stage and sanitized logs, and investigate compatibility on disposable sandbox instances. Reverting the version floor in the branch does not downgrade the installed SBX binary or automatically restore previous sandbox data. A host CLI downgrade should be coordinated with the official release guidance, especially after daemon/data-format changes.

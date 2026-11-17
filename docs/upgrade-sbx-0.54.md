# Upgrade gate: Docker Sandboxes 0.54.0

- Upstream stable: [v0.54.0](https://github.com/docker/sbx-releases/releases/tag/v0.54.0), published **2026-11-16**.
- Baseline: `main` at `1e1fb3f2b7c8e30c0a950cdc51ffd6890c438ddf`, minimum SBX 0.53.0.
- New minimum: **0.54.0**. Existing Kits v3, custom workloads, mixins, MCP registration, and Vertex adapter are intentionally unchanged.
- This is a security and compatibility gate, **not** a runtime compatibility claim.

## Upgrade impact and security

0.54.0 hardens generated SSH configuration against crafted host/user names on older OpenSSH clients. **After upgrading, rerun `sbx setup ssh` and, if using cloud SSH, `sbx --cloud setup ssh`.** Generated SSH configuration is not refreshed automatically.

Clone-mode Git remote transport now uses the host-user-restricted daemon socket rather than an unauthenticated localhost TCP port. Restart existing clone-mode sandboxes to refresh their Git remote configuration; fetching requires the sandbox to be running. Do **not** enable `clone.legacyTcpRemote` as a general workaround: it exposes repository contents and history to other local host accounts. The default transport rejects publishing sandbox TCP port 9418.

Saved mounts that resolve to a different source directory are refused at startup. Investigate and explicitly unmount/remount only after verifying host paths and preserving data; do not bypass the protection. Existing kit permissions may require renewed approval because permission digests changed.

`sbx ports` is deprecated in favor of `sbx port ls/publish/unpublish`; no existing launcher command needs an automatic rewrite. TLS post-quantum exchange is enabled by default. Only for diagnosed TLS-inspection incompatibility, consider `sbx settings set tls.postQuantumKeyExchange false` followed by `sbx daemon restart`, and document the security trade-off. Never disable it preemptively. Root-run CLI ignores inherited home/XDG/storage overrides; stop old custom root daemons before upgrading if applicable.

MCP gateway mode and servers are now visible in `sbx inspect`; inspect does not replace `sbx mcp ls` for host registrations. The release also improves cloud policy inheritance, kit validation diagnostics, and SSH forwarding.

## Owner preflight on trusted macOS

Back up sandbox-local state and unpushed commits before changing runtime or recreating sandboxes.

```bash
brew upgrade docker/tap/sbx
sbx version --json
sbx daemon restart
sbx setup ssh
# Only if cloud SSH is used:
sbx --cloud setup ssh
sbx mcp inspect context7
sbx mcp ls
```

Review clone-mode remotes, port 9418, static mount origins and permission prompts. Do not remove host Context7 credentials or change global settings merely to make tests pass.

## Manual macOS smoke — owner only

From a clean checkout of this PR HEAD, with configured kit builder, host Context7 registration, credentials and local Vertex overlay:

```bash
./tests/validate.sh
SBX_PROFILE=personal ./tests/smoke.sh claude
SBX_PROFILE=personal ./tests/smoke.sh codex
SBX_PROFILE=personal ./tests/smoke.sh opencode
SBX_PROFILE=personal ./tests/smoke.sh antigravity
SBX_PROFILE=personal ./tests/smoke.sh junie
SBX_PROFILE=client ./tests/smoke.sh copilot
SBX_PROFILE=client ./tests/smoke.sh claude
```

Additionally manually verify actual agent launches, Context7 MCP tool use and repeated `sbx mcp load`, clone-mode Git socket transport and worktrees, SSH generated configuration, workspace/static mounts and host isolation, network policy, and secret substitution for Claude/Vertex. Inspect `sbx port ls <SANDBOX>` and exercise publish/unpublish only with a disposable sandbox and approved localhost port. Do not expose port 9418 or enable legacy TCP transport. Confirm disposable cleanup and preservation of all active sandboxes.

For approved authenticated model probes only:

```bash
SBX_PROFILE=personal SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
SBX_PROFILE=client SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
```

No full nested-virtualization sandbox smoke is run on GitHub-hosted macOS runners. Offline GitHub CI is not a substitute for runtime tests.

## Evidence / release gate

**Manual macOS smoke: PENDING / NOT RUN**

| Gate | Status | Evidence / notes |
| --- | --- | --- |
| CLI and daemon 0.54.0+, SSH setup regenerated | PENDING | |
| Native kit inspect and seven environment plans | PENDING | |
| Personal Claude, Codex, OpenCode, Antigravity, Junie | PENDING | |
| Client Copilot and Claude/Vertex | PENDING | |
| Context7 OAuth and gateway; repeat MCP load | PENDING | |
| Clone Git transport, worktrees, mounts and host isolation | PENDING | |
| Port management, network policy, permission prompts | PENDING | |
| Authenticated model probes (approved only) | NOT RUN | |
| Cleanup and preservation of active sandbox data | PENDING | |

Record exact client/daemon versions, tested PR SHA, redacted logs, PASS/FAIL/BLOCKED and cleanup result. Missing credentials are BLOCKED, not PASS. Do not mark PR ready for merge without owner-confirmed PASS. If a gate fails, keep the PR Draft and document the failure before making further changes.

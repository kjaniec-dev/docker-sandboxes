# Upgrade gate: Docker Sandboxes 0.53.0

- Upstream stable: [v0.53.0](https://github.com/docker/sbx-releases/releases/tag/v0.53.0), published **2026-11-11**. Version 0.52.0 was skipped.
- Baseline: `main` at `949e2b98c9ca42cc0eec2fe142720210a2844d31` requires 0.51.0+.
- New minimum: **0.53.0**. This is a security/compatibility gate, **not** a claim that every kit or model was tested.
- The existing Kits v3 architecture, kit pins, custom workloads, MCP registration, Vertex secret adapter and smoke harness remain unchanged.

## Why raise the floor?

The 0.53.0 stable release adds validation of saved mount metadata against the original static host mount sources when restarting sandboxes; rejects inconsistent or redirected mount sources; and strengthens cleanup against sandbox-name reuse. It also changes command behavior, including agent entrypoint argument handling, secret-provider execution from a temporary working directory, and HTTP policy matching.

The repository's normal launcher uses `sbx env run` and `sbx run --name`; client Claude and Junie use `sbx env exec`. There are no unsupported `--detach`, `--privileged` or `--detach-keys` flags on those exec paths. Do not remove the Context7 host-global registration or its OAuth credentials. No kit/mixin rewrite is justified by the release notes alone.

## Owner preflight — macOS

On a trusted Mac, with backups of sandbox-local files and unpushed commits, and authorization for changes to the SBX installation/daemon:

```bash
brew upgrade docker/tap/sbx
sbx version --json
sbx daemon restart
sbx mcp inspect context7
```

Confirm **client 0.53.0+** and a compatible daemon. Before recreating any existing sandbox, verify original static mount paths still resolve to their intended host directories. A failed mount metadata check is **BLOCKED**: restore the original path or preserve files and recreate deliberately. Never delete active project sandboxes as part of this PR's tests.

Review any local secret-reference providers: host executables must resolve via absolute `PATH` entries, configuration paths must be absolute, and project-local asdf/mise selections may no longer apply when the provider runs from a temporary directory. Review network HTTP policies that previously relied on case-sensitive path/query matching; 0.53.0 treats ASCII letters in these fields case-insensitively. No automatic policy rewrite is included.

## Manual macOS smoke matrix — owner only

Run on a clean checkout of **this PR SHA**, with configured native kit builder, host Context7 registration, secrets and overlays:

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

Each smoke run creates a **disposable** sandbox, checks fresh/restart/recreate and cleans up on success. The owner must also manually verify the actual CLI agent launch, native Context7 MCP tool availability and repeated `sbx mcp load` on an existing sandbox; worktree/workspace mount isolation and policy behavior; Claude Code and Vertex AI secret substitution; and that sandbox files/commits are not lost. Test any approved model authentication separately:

```bash
SBX_PROFILE=personal SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
SBX_PROFILE=client SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
```

Do not run authenticated requests without approved credentials. The client profile requires `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION` and the machine-local overlay. No GitHub-hosted macOS job should attempt the full nested-virtualization runtime smoke.

## Owner evidence and gate

**Manual macOS smoke: PENDING / NOT RUN**

| Gate | Status | Evidence / notes |
| --- | --- | --- |
| Native kit inspect + 7 env plans | PENDING | |
| Personal Claude / Codex / OpenCode / Antigravity / Junie | PENDING | |
| Client Copilot / Claude Vertex | PENDING | |
| Context7 OAuth, MCP gateway, repeated launch | PENDING | |
| Worktrees, workspace mounts, host isolation, HTTP policies | PENDING | |
| Authenticated model probes (optional, approved only) | NOT RUN | |
| Disposable sandbox cleanup and active sandbox preservation | PENDING | |

Record exact SBX client/daemon versions, tested PR HEAD SHA, command logs (redact secrets), PASS/FAIL/BLOCKED and cleanup outcome. A missing credential or unavailable macOS environment is **BLOCKED**, not PASS. GitHub Actions offline lint/tests are a separate gate and do not establish runtime compatibility.

## Rollback

Leave the PR Draft/unmerged on any blocker. If already deployed, revert the version-floor change only after assessing any new 0.53.0 security and mount behavior. Reverting Git files does not downgrade the CLI or restore sandbox-local data.

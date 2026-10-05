# Codex rewrite prompt

Replace the current implementation of `kjaniec-dev/docker-sandboxes` with the clean SBX 0.46+ V3
architecture represented by this artifact.

Treat the current repository and Git history as a **behavioral reference only**. Do not preserve its
file structure, helper framework, V2 lifecycle, rebuild workflow, or internal abstractions.

## Required target behavior

Personal profile:

- Claude Code
- Codex
- OpenCode
- Antigravity
- Junie

Client profile:

- Claude Code using Vertex AI
- GitHub Copilot CLI

Shared behavior:

- one shared V3 `dev` mixin,
- native `sbx skills` shared store,
- native SBX MCP gateway for Context7 and other remote/host MCP servers,
- Serena kept as a sandbox-local stdio MCP server,
- common agent instructions through `agent-context`,
- common developer network policy in the dev mixin,
- provider-specific auth/network owned by official agent kits or the Vertex mixin,
- one small launcher implementation,
- declarative `sbx env` files,
- deterministic sandbox naming,
- project-local `.worktrees/` safety,
- behavioral validation/smoke tests.

## Architecture constraints

- SBX minimum version: 0.46.0.
- Sandbox Kit schema: V3 only.
- Prefer official Docker V3 workloads and mixins.
- Claude and OpenCode use local minimal shell workloads plus Docker's official agent mixins while
  their official standalone workload names still collide with SBX built-ins.
- Do not copy Docker's large Claude/OpenCode workload descriptors just to rename them.
- Client Claude uses the same Claude shell workload + official Claude mixin + local Vertex policy.
- Preserve the client's already-working ADC/WIF mechanism; do not invent a new enterprise auth flow.
- Host Podman Desktop requires no special SBX backend code.
- Do not run Serena through `sbx mcp --command`; that would execute it on the host.

## Delete legacy mechanisms after parity

Remove all V2 kits, per-agent harness directories, per-agent rebuilds, template tar handling,
`harness_root`, infrastructure checkout mounts, generated harness scaffolding, manual shared-skills
linking, duplicate Context7 setup, and grep-based wiring tests.

Do not create `legacy/`, `old/` or `v2/` directories. Git history is the archive.

## Verification order

1. Inspect the current repository only to inventory behavior that must survive.
2. Implement/validate the shared dev mixin.
3. Prove Codex with official V3 workload + dev mixin.
4. Prove Antigravity and Junie.
5. Prove Claude and OpenCode through their local thin workloads + official agent mixins.
6. Prove client Copilot.
7. Prove client Claude Vertex on the client machine using the existing approved ADC/WIF path.
8. Verify Context7 through SBX MCP, Serena inside the sandbox, shared skills, Playwright/Chromium,
   Java/Python/Go/Node tooling, stop/start and delete/recreate lifecycle.
9. Delete the old implementation completely.
10. Rerun the full matrix.

Keep the resulting code materially smaller than the implementation it replaces. If a refactor
introduces a new generic Bash framework, stop and look for the native SBX feature that makes it
unnecessary.

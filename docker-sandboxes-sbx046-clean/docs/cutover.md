# Cutover from the old implementation

Use Git history as the archive. Do not keep a `legacy/`, `v2/` or `old/` tree after cutover.

## Preserve behavior, not structure

Before deleting the old files, verify the clean tree covers:

- deterministic per-agent/per-repository sandbox names,
- project-local `.worktrees/` guard,
- shared development toolchain,
- native SBX shared skills,
- Context7 through the MCP gateway,
- Serena as a sandbox-local MCP server,
- Playwright + Chromium,
- common instructions,
- agent-specific authentication,
- personal five-agent matrix,
- client Claude Vertex + Copilot matrix.

## Delete after parity

The replacement is designed to make these concepts disappear:

```text
harnesses/
shared/
per-agent root launcher implementations
*-sbx-rebuild
shared/rebuild.sh
sbx-new-harness
V2 kit specs
harness_root / HARNESS_ROOT
infrastructure repository read-only mount
.build/*.tar
docker image save
sbx template load
per-agent toolchain Dockerfiles
per-agent Context7 configuration
manual shared-skills lifecycle
large grep/wiring test suite
```

Recommended cutover:

1. Create a rewrite branch and tag the last working legacy commit.
2. Put this target tree at the repository root.
3. Use old Git history only to compare behavior and recover the client's Vertex auth details.
4. Run `tests/validate.sh`.
5. Smoke personal agents one at a time: Codex, Antigravity, Junie, Claude, OpenCode.
6. Smoke client Copilot and Claude Vertex on the client machine.
7. Remove the old implementation completely.
8. Rerun validation and all seven smokes.
9. Merge with `main` containing only the clean V3 implementation.

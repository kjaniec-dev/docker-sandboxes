# Repository instructions

This repository targets Docker Sandboxes 0.46+ and Sandbox Kit V3 only.

Architecture rules:

- Prefer native SBX capabilities over custom scripts.
- Keep reusable skills in the native `sbx skills` store.
- Keep remote/host MCP servers in the native SBX MCP gateway.
- Keep Serena sandbox-local; never run it as a host `sbx mcp --command` server.
- Put shared tooling, policy and instructions in `mixins/dev`.
- Put only agent-specific launch/auth/provider behavior in workloads or official agent kits.
- Prefer official Docker V3 workloads/mixins over copied descriptors.
- Do not add V2 compatibility, template tar handling, `harness_root`, infrastructure mounts, or per-agent rebuild wrappers.
- Keep Bash small. If structured config mutation is needed, prefer a small standard-library Python helper.
- Validate with `tests/validate.sh` and use `tests/smoke.sh` for real sandbox behavior.

# SBX 0.43 Claude Migration Design

## Context

Docker Sandboxes 0.43.0 is now stable. The repository currently targets
0.42.1, manually mounts the shared skills store, and checks custom template
availability by parsing `sbx template ls --json` before creating a sandbox.
All five harnesses use the same launcher lifecycle, while each harness owns a
different kit, entrypoint, bootstrap, and credential flow.

## Goals

- Make SBX 0.43.0 the minimum supported runtime for every harness.
- Use the native read-only shared skills mount instead of manually mounting and
  linking the skills store.
- Remove the fragile template-listing probe from the shared launcher.
- Keep deterministic sandbox names, direct read/write workspace mounts, the
  `.worktrees/` guard, custom images, kits, and agent-specific behavior.
- Move Claude's normal launch path toward `sbx env` and document a global
  `~/.sbxenv.yaml` with the project workspace and read-only skills policy.
- Keep credentials, session state, and machine-specific paths out of tracked
  files.

## Non-goals

- Rewriting all five harnesses to use one environment file. Their kits and
  authentication/session semantics are intentionally different.
- Changing Node, Go, Java, Maven, Gradle, plugin, MCP, or agent versions.
- Migrating existing sandboxes in place. Existing instances must be recreated
  when their skills mount or kit changes.
- Renaming or recreating stored MCP OAuth secrets automatically. Documentation
  will call out the 0.43 name change and require users to set the new secret.

## Design

### Shared launcher contract

`shared/launcher.sh` will require SBX 0.43.0 or newer and will continue to own
repository discovery, the worktree guard, deterministic naming, sandbox
creation/reuse, and argument forwarding. It will stop requiring `jq` solely for
template discovery and will no longer resolve or mount the host skills store.

Each kit will declare the custom image it needs. The launcher will pass the
kit directly to `sbx create` and explicitly request `--skills=readonly`, so a
host setting cannot accidentally make the shared store writable. The kit
arguments and read-only harness mount remain only where a bootstrap script
needs them.

### Native skills

The host-side `sbx-skills` command remains the source of truth for installing
and pinning the shared skills. SBX mounts that store at the agent's standard
discovery path. Harness bootstraps will no longer create a discovery symlink
or receive `skills_root`; verification will check the native discovery paths.

### Claude environment workflow

Claude will use the 0.43 environment-file workflow for provisioning and a
normal `sbx run` attachment for agent argument forwarding. The documented
user-level file is:

```yaml
schemaVersion: "1"
agent: /absolute/path/to/claude-sbx/harnesses/claude-code/kit
workspace: ${{ env.projectDir }}
skills: readonly
```

The absolute `agent` value is intentionally user-local and is documented as a
placeholder, never committed as a machine path. The tracked kit declares the
custom Claude image and owns network permissions and instructions. Its plugin
bootstrap will be copied into that image at build time, so the kit no longer
needs a runtime `harness_root` argument or a read-only mount of this repository.

The wrapper will validate the repository and skills store, run
`sbx env create --name <deterministic-name>` to apply the global environment,
then attach with `sbx run --name <deterministic-name> -- <claude-args>`. This
preserves model and other Claude arguments without a generated YAML file or
template-listing probe.

### Other harnesses

Codex, OpenCode, Antigravity CLI, and Junie will keep their current shared
`create`/`run` lifecycle in this change. They will consume the same 0.43
launcher and native-skills contract, while preserving Codex/OpenCode default
arguments, Antigravity/Junie entrypoints, and Junie's session-only API key.

## Error handling and migration

- Missing `sbx` reports the 0.43.0 minimum.
- A missing custom image is reported by the native create/load operation rather
  than by a JSON template-listing probe.
- Existing sandboxes are not mutated to change skills access or kit settings;
  the usage guide instructs users to remove and recreate them.
- The usage guide documents the 0.43 MCP OAuth secret rename from
  `mcp:<server>.client_secret` to `mcp:<server>:client_secret`.

## Verification

- Update host mocks and wiring tests for the 0.43 command boundary, native
  skills mode, kit-owned images, and Claude environment invocation.
- Run the complete `make test` suite and Bash syntax checks.
- Run kit validation tests when an SBX 0.43 CLI is available.
- Report that daemon-driven create/attach, credentials, and OAuth require a
  macOS Docker Sandboxes smoke test because the current host has no `sbx` CLI.

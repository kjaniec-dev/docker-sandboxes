# Claude, Codex, OpenCode, Antigravity, and Junie Docker Sandboxes

Reusable Docker Sandbox harnesses for Claude Code, Codex, OpenCode, Antigravity
CLI, and Junie. Each harness gives the selected Git repository a writable
workspace inside its own sandbox while the rest of the host stays outside
that workspace.

All harnesses provide the same development toolchain: Node.js 24.19.0, Go
1.26.6, Python and uv, Serena, Docker Engine and Compose, Playwright CLI,
OpenJDK 25, Maven, Gradle, and common Git, database, shell, and search tools.
All five agents use SBX's native read-only `skills` mode backed by one shared
`sbx` skills store with Superpowers, pinned Caveman and Playwright CLI skills.
Agent-specific MCP registrations and Claude plugins remain in sandbox bootstrap
scripts.

## Quick start

Requires Docker Sandboxes 0.43.0 or newer, Git and jq on the host, plus Docker
to build the custom images. Full sandbox kits configure each agent. Direct
harnesses use `sbx create` and `sbx run --name`; Claude uses the user-level
`~/.sbxenv.yaml` with `sbx env create --name` and then `sbx run --name`. No
launcher generates or rewrites an environment file. The public launcher
commands stay the same.

Build the templates from this repository:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
./bin/opencode-sbx-rebuild
./bin/agy-sbx-rebuild
./bin/junie-sbx-rebuild
```

The launcher populates the host skills store on first launch, and SBX exposes it
to agents through native read-only skills access. To install skills ahead of
time or update Superpowers and Playwright later (Caveman stays pinned):

```bash
./bin/sbx-skills
./bin/sbx-skills --update
```

Use `./bin/sbx-policy-audit` to review blocked network requests across
sandboxes, and `./bin/sbx-new-harness <name>` to scaffold an additional
harness with its root delegates and layout test.

After upgrading to SBX 0.43.0, remove each existing sandbox once with
`sbx rm <sandbox-name>` and launch it again so the new kit and native skills
settings apply. This discards its sessions and sandbox-local configuration, not
the mounted repository. Existing toolchain images can be reused unless the
image or shared toolchain changed. Claude also requires the user-level
`~/.sbxenv.yaml` described in [the usage guide](docs/usage.md).

SBX 0.43.0 no longer reads MCP OAuth client secrets named
`mcp:<server>.client_secret`. Re-set each one without inspecting or migrating
its value:

```bash
sbx secret set mcp:<server>:client_secret
```

Optionally make the commands available on your `PATH`:

```bash
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/bin/claude-sbx" "$HOME/.local/bin/claude-sbx"
ln -sfn "$PWD/bin/codex-sbx" "$HOME/.local/bin/codex-sbx"
ln -sfn "$PWD/bin/opencode-sbx" "$HOME/.local/bin/opencode-sbx"
ln -sfn "$PWD/bin/agy-sbx" "$HOME/.local/bin/agy-sbx"
ln -sfn "$PWD/bin/junie-sbx" "$HOME/.local/bin/junie-sbx"
ln -sfn "$PWD/bin/agy-sbx-rebuild" "$HOME/.local/bin/agy-sbx-rebuild"
ln -sfn "$PWD/bin/claude-sbx-rebuild" "$HOME/.local/bin/claude-sbx-rebuild"
ln -sfn "$PWD/bin/codex-sbx-rebuild" "$HOME/.local/bin/codex-sbx-rebuild"
ln -sfn "$PWD/bin/opencode-sbx-rebuild" "$HOME/.local/bin/opencode-sbx-rebuild"
ln -sfn "$PWD/bin/junie-sbx-rebuild" "$HOME/.local/bin/junie-sbx-rebuild"
```

Then, from any Git repository, ensure project-local worktrees are ignored and
start the harness you need:

```bash
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
claude-sbx
# or
codex-sbx
# or
opencode-sbx
# or
agy-sbx
# or
junie-sbx
```

The `grep`/`echo` command modifies the target repository's `.gitignore` when
needed. Review and commit that change in the target repository if appropriate.

The harness commands create distinct sandboxes for the same repository, so
their agent configuration and sessions do not overlap. See [the usage guide](docs/usage.md)
for authentication, ports, verification, rebuilds, and extension guidance.

## Security model

The selected repository is mounted read/write, so an agent can modify or delete
files in that repository, including Git metadata. Other host paths are not
exposed unless explicitly added as workspaces. Direct non-Claude launchers
mount this infrastructure repository read-only when it differs from the target
so bootstrap and verification scripts remain available. Claude's bootstrap is
baked into its image and does not require that mount. The host skills store is
exposed through SBX's native read-only skills mode; skill changes made by one
sandbox cannot modify the host store. Authentication is managed outside the
images; do not commit credentials or session state.

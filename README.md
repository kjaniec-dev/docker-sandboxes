# Claude, Codex, OpenCode, Antigravity, and Junie Docker Sandboxes

Reusable Docker Sandbox harnesses for Claude Code, Codex, OpenCode, Antigravity
CLI, and Junie. Each harness gives the selected Git repository a writable
workspace inside its own sandbox while the rest of the host stays outside
that workspace.

All harnesses provide the same development toolchain: Node.js 24.19.0, Go
1.26.6, Python and uv, Serena, Docker Engine and Compose, Playwright CLI,
OpenJDK 25, Maven, Gradle, and common Git, database, shell, and search tools.
All five agents use one shared `sbx` skills store with Superpowers, pinned
Caveman and Playwright CLI skills. Agent-specific MCP registrations and Claude
plugins remain in sandbox bootstrap scripts.

## Quick start

Requires Docker Sandboxes 0.42.1 or newer, Git and jq on the host, plus Docker
to build the custom images. Full sandbox kits configure each agent;
`sbx create` provisions missing instances from the kit and `sbx run --name` reattaches; no generated environment files are needed. The public launcher commands stay the same.

Build the templates from this repository:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
./bin/opencode-sbx-rebuild
./bin/agy-sbx-rebuild
./bin/junie-sbx-rebuild
```

Skills install automatically on first launch. To install them ahead of time or
update Superpowers and Playwright later (Caveman stays pinned):

```bash
./bin/sbx-skills
./bin/sbx-skills --update
```

Migrating from the old launchers requires removing each old sandbox once with
`sbx rm <sandbox-name>` and launching it again. This discards its sessions and
sandbox-local configuration, not the mounted repository. Existing toolchain
images can be reused; this migration alone does not require rebuilding them.

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
exposed unless explicitly added as workspaces. This infrastructure repository
is mounted read-only when it differs from the target repository, so harness
bootstrap and verification scripts remain available. The shared skills store
is also mounted read/write: skill changes made by one sandbox affect the host
store and other sandboxes. Authentication is managed outside the images; do
not commit credentials or session state.

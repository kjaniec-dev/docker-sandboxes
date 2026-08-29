# Claude and Codex Docker Sandboxes

Reusable Docker Sandbox harnesses for Claude Code and Codex. Each harness gives
the selected Git repository a writable workspace inside its own sandbox while
the rest of the host stays outside that workspace.

Both harnesses provide the same development toolchain: Node.js 24.19.0, Go
1.26.6, Python and uv, Serena, Docker Engine and Compose, Playwright CLI,
OpenJDK 25, Maven, Gradle, and common Git, database, shell, and search tools.
The Codex bootstrap registers Serena and Context7 as MCP servers, installs
Superpowers into native Codex skill discovery, and installs the Playwright CLI
skills for Codex.

## Quick start

Build the templates from this repository:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
```

Optionally make the commands available on your `PATH`:

```bash
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/bin/claude-sbx" "$HOME/.local/bin/claude-sbx"
ln -sfn "$PWD/bin/codex-sbx" "$HOME/.local/bin/codex-sbx"
ln -sfn "$PWD/bin/claude-sbx-rebuild" "$HOME/.local/bin/claude-sbx-rebuild"
ln -sfn "$PWD/bin/codex-sbx-rebuild" "$HOME/.local/bin/codex-sbx-rebuild"
```

Then, from any Git repository, ensure project-local worktrees are ignored and
start the harness you need:

```bash
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
claude-sbx
# or
codex-sbx
```

The `grep`/`echo` command modifies the target repository's `.gitignore` when
needed. Review and commit that change in the target repository if appropriate.

The two commands create distinct sandboxes for the same repository, so their
agent configuration and sessions do not overlap. See [the usage guide](docs/usage.md)
for authentication, ports, verification, rebuilds, and extension guidance.

## Security model

The selected repository is mounted read/write, so an agent can modify or delete
files in that repository, including Git metadata. Other host paths are not
exposed unless explicitly added as workspaces. This infrastructure repository
is mounted read-only when it differs from the target repository, so harness
bootstrap and verification scripts remain available. Authentication is managed
outside the images; do not commit credentials or session state.

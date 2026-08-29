# Usage

## Requirements

- macOS
- Docker Desktop with Docker Sandboxes (`sbx`) support
- Git

Install Docker Sandboxes, check its platform requirements, and sign in by
following Docker's official [installation guide](https://docs.docker.com/ai/sandboxes/install/).

Check the local installation:

```bash
sbx version
docker version
```

## Build the harness templates

From this repository, build one or both templates:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
```

These commands build `claude-sbx:local` and `codex-sbx:local`, export their
images under `.build/`, and load them into Docker Sandboxes. `make rebuild` is
kept as a compatibility alias for the Claude rebuild; use `make rebuild-claude`
or `make rebuild-codex` when choosing explicitly.

## Put commands on PATH

From this repository:

```bash
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/bin/claude-sbx" "$HOME/.local/bin/claude-sbx"
ln -sfn "$PWD/bin/codex-sbx" "$HOME/.local/bin/codex-sbx"
ln -sfn "$PWD/bin/claude-sbx-rebuild" "$HOME/.local/bin/claude-sbx-rebuild"
ln -sfn "$PWD/bin/codex-sbx-rebuild" "$HOME/.local/bin/codex-sbx-rebuild"

grep -q 'HOME/.local/bin' "$HOME/.zshrc" || \
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
```

## First start: Codex

Run this once after installing Docker Sandboxes. Replace the placeholder paths
with the harness checkout and the Git repository where you want to use Codex.

```bash
# In the harness repository
sbx login
./bin/codex-sbx-rebuild

# Authenticate with OpenAI on the host before creating a sandbox.
sbx secret set openai --oauth

# In the target Git repository
cd /path/to/target-repository
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
codex-sbx
```

`sbx secret set openai --oauth` opens the browser-based sign-in flow and keeps
the resulting credential on the host. The sandbox does not receive the token.

## First start: Claude Code

For an Anthropic API key, authenticate before creating a sandbox:

```bash
# In the harness repository
sbx login
./bin/claude-sbx-rebuild
sbx secret set anthropic

# In the target Git repository
cd /path/to/target-repository
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
claude-sbx
```

If you use a Claude subscription instead of an API key, run `claude-sbx` and
then use `/login` inside Claude Code. This is the subscription authentication
flow supported by Docker Sandboxes.

## Start a harness

In the target Git repository, project-local worktrees must be ignored:

```bash
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
```

This command changes the target repository: it appends `.worktrees/` to that
repository's `.gitignore` only when the entry is absent. Review and commit this
change in the target repository if it is appropriate for that project.

Start Claude Code:

```bash
claude-sbx
```

Start Codex:

```bash
codex-sbx
```

Both harnesses use direct workspace mode: the target repository is mounted
read/write at its original absolute path. They intentionally do not use
`--clone`. When the target differs from this repository, the harness source is
also mounted read-only for bootstrap and verification. The `.worktrees/` guard
is unchanged and exits before sandbox creation when the directory is not
ignored by Git.

Sandbox names are deterministic but separate:

| Harness | Name | Template |
| --- | --- | --- |
| Claude Code | `claude-<repo-slug>-<8-hex-path-digest>` | `claude-sbx:local` |
| Codex | `codex-<repo-slug>-<8-hex-path-digest>` | `codex-sbx:local` |

Running either command again reattaches to that harness's sandbox. Claude and
Codex never share an agent-managed configuration directory or sandbox identity.

## Authentication

Authentication is not baked into either image.

For Codex, manage host-side credentials with either:

```bash
sbx secret set openai --oauth
```

or the interactive `sbx run codex` flow. Claude authentication is likewise
managed interactively by Docker Sandboxes and Claude Code. Do not add API keys,
credentials, or session state to the Dockerfiles, kits, or repository.

## Worktrees and IDEs

Direct mode uses the host checkout, so edits are immediately visible in IDEs.
For a project-local worktree:

```text
repo/
├── .git/
├── .worktrees/
│   └── feature-name/
└── ...
```

Open that directory with the IDE of your choice. Do not create a sibling
worktree outside the mounted repository and use it as the only workspace.

## Verify a sandbox

From the target repository, source the matching wrapper to calculate its
deterministic name, then run the matching verification script. For Claude:

```bash
source /path/to/claude-sbx/bin/claude-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash /path/to/claude-sbx/harnesses/claude-code/scripts/verify.sh
```

For Codex:

```bash
source /path/to/claude-sbx/bin/codex-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash /path/to/claude-sbx/harnesses/codex/scripts/verify.sh
```

Each verification checks its agent CLI plus the shared toolchain, pinned
Node/Go versions, Serena, Playwright CLI, OpenJDK 25, Maven, Gradle, and Docker
Compose. Codex bootstrap idempotently registers Serena and Context7 as MCP
servers, installs Superpowers into `~/.agents/skills/`, and installs the
Playwright CLI skills for Codex. The Codex kit instructs the agent to use
`playwright-cli` for browser and frontend validation.

## Ports

After a sandbox is created, publish a development port using its name:

```bash
sbx ports <sandbox-name> --publish 3000:3000
```

Use a different port mapping as needed for application servers.

## Rebuild and recreate

Existing sandboxes retain their current VM state and template. After changing a
Dockerfile, shared toolchain script, or harness kit:

1. Rebuild the appropriate template with `claude-sbx-rebuild` or
   `codex-sbx-rebuild`.
2. Remove that harness's existing sandbox: `sbx rm <sandbox-name>`.
3. Run `claude-sbx` or `codex-sbx` again from the target repository.

Kit instructions and network policy apply only during sandbox creation, so a
kit change also requires recreation.

## Add a future harness

New harnesses belong under `harnesses/<name>/` and should own their Dockerfile,
kit, launcher, bootstrap, and verification scripts. Add thin root delegates in
`bin/`, use a unique template tag and sandbox-name prefix, share the installer
scripts in `shared/`, and extend the host-side tests. Antigravity CLI and
OpenCode are reserved as future harnesses; no placeholder implementations are
included.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `sbx: command not found` | Install Docker Sandboxes and sign in using Docker's [installation guide](https://docs.docker.com/ai/sandboxes/install/), then open a new terminal. |
| `template 'claude-sbx:local' is not loaded` or `template 'codex-sbx:local' is not loaded` | In this harness repository, run `claude-sbx-rebuild` or `codex-sbx-rebuild` for the matching harness, then try again. |
| `.worktrees/ is not ignored by Git` | In the target repository, add `.worktrees/` to `.gitignore`, review the resulting Git change, then run the harness again. |

If bootstrap or authentication needs network access that the kit does not
allow, inspect the policy log:

```bash
sbx policy log <sandbox-name>
```

Add only the required domain to the appropriate harness kit, then recreate the
sandbox. Claude bootstrap is idempotent and installs its plugins; Codex
bootstrap is also idempotent and registers Serena and Context7 when their MCP
entries are missing or invalid.

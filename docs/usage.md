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

From this repository, build one or more templates:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
./bin/opencode-sbx-rebuild
./bin/antigravity-sbx-rebuild
```

These commands pull the current agent base image, build `claude-sbx:local`,
`codex-sbx:local`, `opencode-sbx:local`, and `antigravity-sbx:local`, export
their images under `.build/`, and load them into Docker Sandboxes.
`make rebuild` is kept as a compatibility alias for the Claude rebuild; use
`make rebuild-claude`, `make rebuild-codex`, `make rebuild-opencode`, or
`make rebuild-antigravity` when choosing explicitly. (The Antigravity build
uses the neutral shell base image plus a pinned Antigravity CLI release.)

## Put commands on PATH

From this repository:

```bash
mkdir -p "$HOME/.local/bin"
ln -sfn "$PWD/bin/claude-sbx" "$HOME/.local/bin/claude-sbx"
ln -sfn "$PWD/bin/codex-sbx" "$HOME/.local/bin/codex-sbx"
ln -sfn "$PWD/bin/opencode-sbx" "$HOME/.local/bin/opencode-sbx"
ln -sfn "$PWD/bin/antigravity-sbx" "$HOME/.local/bin/antigravity-sbx"
ln -sfn "$PWD/bin/antigravity-sbx-rebuild" "$HOME/.local/bin/antigravity-sbx-rebuild"
ln -sfn "$PWD/bin/claude-sbx-rebuild" "$HOME/.local/bin/claude-sbx-rebuild"
ln -sfn "$PWD/bin/codex-sbx-rebuild" "$HOME/.local/bin/codex-sbx-rebuild"
ln -sfn "$PWD/bin/opencode-sbx-rebuild" "$HOME/.local/bin/opencode-sbx-rebuild"

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

## First start: OpenCode

Build and authenticate OpenCode before creating its sandbox:

```bash
# In the harness repository
sbx login
./bin/opencode-sbx-rebuild

# Store one or more provider credentials on the host
sbx secret set openai
sbx secret set anthropic
sbx secret set google
sbx secret set xai
sbx secret set groq
sbx secret set openrouter

# In the target Git repository
cd /path/to/target-repository
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
opencode-sbx
```

For OpenCode Go only mode, configure its host-side API key before creating the
sandbox:

```bash
export OPENCODE_API_KEY="your-api-key"
sbx secret set-custom \
  --host opencode.ai \
  --env OPENCODE_API_KEY \
  --value "$OPENCODE_API_KEY"
```

Docker Sandboxes keeps this value on the host and injects it only for requests
to `opencode.ai`. Bootstrap sets `enabled_providers` to `opencode-go`, so no
other provider is enabled and no
`/connect` step is needed. Recreate existing sandboxes after adding this
global secret. Do not put provider values in this repository, image, kit, or
OpenCode config. Host-level OpenCode config is not inherited by this harness;
bootstrap creates managed global config inside the sandbox.

## First start: Antigravity CLI

Build the Antigravity template before creating its sandbox:

```bash
# In the harness repository
sbx login
./bin/antigravity-sbx-rebuild

# In the target Git repository
cd /path/to/target-repository
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
antigravity-sbx
```

On first start, Antigravity CLI prints a Google Sign-In URL. Open it in a host
browser and complete the login. The credential is stored in sandbox state and
reused on reattach; sign in again only after removing and recreating the
sandbox.

Alternatively, use a Gemini API key. Store it on the host before creating the
sandbox:

```bash
sbx secret set-custom \
  --host generativelanguage.googleapis.com \
  --env GEMINI_API_KEY \
  --value "$GEMINI_API_KEY"
```

Do not put Google credentials in this repository, image, kit, or Antigravity
config files.

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

Start OpenCode:

```bash
opencode-sbx
```

Start Antigravity CLI:

```bash
antigravity-sbx
```

All harnesses use direct workspace mode: the target repository is mounted
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
| OpenCode | `opencode-<repo-slug>-<8-hex-path-digest>` | `opencode-sbx:local` |
| Antigravity CLI | `antigravity-<repo-slug>-<8-hex-path-digest>` | `antigravity-sbx:local` |

Running a command again reattaches to that harness's sandbox. Claude, Codex,
OpenCode, and Antigravity never share an agent-managed configuration directory
or sandbox identity.

## Authentication

Authentication is not baked into either image.

For Codex, manage host-side credentials with either:

```bash
sbx secret set openai --oauth
```

or the interactive `sbx run codex` flow. Claude authentication is likewise
managed interactively by Docker Sandboxes and Claude Code. Do not add API keys,
credentials, or session state to the Dockerfiles, kits, or repository.

For OpenCode, use the provider commands listed in [First start: OpenCode](#first-start-opencode).
OpenCode Zen requires `sbx secret set-custom` with host `opencode.ai`; its
`OPENCODE_API_KEY` value is never written to tracked files or the sandbox image.

For Antigravity CLI, use Google Sign-In inside the sandbox (once per sandbox
lifetime) or the `GEMINI_API_KEY` flow from
[First start: Antigravity CLI](#first-start-antigravity-cli).

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

For OpenCode:

```bash
source /path/to/claude-sbx/bin/opencode-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash /path/to/claude-sbx/harnesses/opencode/scripts/verify.sh
```

For Antigravity CLI:

```bash
source /path/to/claude-sbx/bin/antigravity-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash /path/to/claude-sbx/harnesses/antigravity-cli/scripts/verify.sh
```

Each verification checks its agent CLI plus the shared toolchain, pinned
Node/Go versions, Serena, Playwright CLI, OpenJDK 25, Maven, Gradle, and Docker
Compose. Codex bootstrap idempotently registers Serena and Context7 as MCP
servers, installs Superpowers and the pinned Caveman skill into
`~/.agents/skills/`, and installs the Playwright CLI skills for Codex. The
Antigravity bootstrap idempotently registers Serena and Context7 and links
Superpowers, Caveman, and Playwright skills into Antigravity's global skill
directory. The Codex kit instructs the agent to use `playwright-cli` for
browser and frontend validation.

## Ports

After a sandbox is created, publish a development port using its name:

```bash
sbx ports <sandbox-name> --publish 3000:3000
```

Use a different port mapping as needed for application servers.

## Rebuild and recreate

Existing sandboxes retain their current VM state and template. After changing a
Dockerfile, shared toolchain script, or harness kit:

1. Rebuild the appropriate template with `claude-sbx-rebuild`,
   `codex-sbx-rebuild`, `antigravity-sbx-rebuild`,
   `make rebuild-opencode`, or `make rebuild-antigravity`.
2. Remove that harness's existing sandbox with `sbx rm <sandbox-name>`.
3. Run the matching harness command again from the target repository.

Kit instructions and network policy apply only during sandbox creation, so a
kit change also requires recreation.

## Add a future harness

New harnesses belong under `harnesses/<name>/` and should own their Dockerfile,
kit, launcher, bootstrap, and verification scripts. Add thin root delegates in
`bin/`, use a unique template tag and sandbox-name prefix, share the installer
scripts in `shared/`, and extend the host-side tests. Claude Code, Codex,
OpenCode, and Antigravity CLI are implemented.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `sbx: command not found` | Install Docker Sandboxes and sign in using Docker's [installation guide](https://docs.docker.com/ai/sandboxes/install/), then open a new terminal. |
| `template 'claude-sbx:local'`, `template 'codex-sbx:local'`, `template 'opencode-sbx:local'`, or `template 'antigravity-sbx:local'` is not loaded | In this harness repository, run the matching rebuild command, including `make rebuild-opencode` for OpenCode or `make rebuild-antigravity` for Antigravity CLI, then try again. |
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

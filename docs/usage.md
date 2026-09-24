# Usage

## Requirements

- macOS
- Docker Sandboxes (`sbx`), minimum version 0.43.0
- Docker Desktop / Docker Engine for building the custom images
- Git and jq on the host (`brew install jq`)

Install Docker Sandboxes, check its platform requirements, and sign in by
following Docker's official [installation guide](https://docs.docker.com/ai/sandboxes/install/).

Check the local installation:

```bash
sbx version
docker version
```

`sbx` is a standalone installation. The host Docker daemon is needed for our
image builds; sandbox execution uses the Docker Sandboxes runtime.

## Docker Sandboxes 0.43.0

Docker Sandboxes 0.43.0 is the minimum supported runtime. See the official
[release notes](https://docs.docker.com/ai/sandboxes/release-notes/) for the
complete change list.

The five harnesses share launcher and image-rebuild code in
`shared/launcher.sh` and `shared/rebuild.sh`. Agent-specific commands,
authentication, bootstrap scripts, and kits remain under each harness.
Launcher-only updates apply to existing sandboxes on the next invocation.

Kits are `kind: sandbox`. Claude, Codex and OpenCode inherit their native agent
defaults and declare their custom images; Antigravity and Junie declare their
own entrypoints. All launchers pass the kit and workspace to
`sbx create --name`, request native `--skills=readonly`, and then attach with
`sbx run --name`. Claude passes its local v2 kit directly to `sbx create`.
Launchers do not generate or require environment files. Agent bootstrap runs
synchronously as user 1000 via the kit's `setup.install`, before attachment.
Junie API keys are supplied only to the second, session attachment command.

### 0.43 changes

- Native `skills` access supports `off`, `readonly`, and `readwrite`; these
  harnesses explicitly use read-only access instead of manually mounting or
  symlinking a host skills directory.
- `sbx env` supports `${{ env.projectDir }}`, and every environment command
  accepts `--name`. The launchers forward agent arguments after the
  `sbx run --name ... --` separator without rewriting them.
- `sbx inspect <sandbox-name>` and `sbx daemon inspect` show mount information;
  use them to check the direct workspace and native skills mounts.
- Signed git kits are materialized from commit blobs and cached checkouts are
  verified against their manifests. Git configuration injection is hardened,
  and SBX warns when a stored credential has no binding authorizing it for a
  sandbox.

On first creation, sbx asks which credentials the custom v2 kit may use.
For Codex with an existing ChatGPT login, skip the API-key option and approve
OpenAI OAuth. A stored login alone is insufficient: the kit also needs this
binding. Non-interactive creation cannot ask and may start without usable
credentials. See [Docker credential bindings](https://docs.docker.com/ai/sandboxes/configuration/credentials/).

The custom images copy the shared toolchain installers; the Claude image also
copies its plugin bootstrap into the image. Installers clean Go, uv and npm
build/download caches in the same image layer, retaining installed tools and
Playwright browsers. Rebuild templates to apply this size reduction; existing
images and sandboxes are unaffected.

Chromium is installed as `agent`, in that user's browser cache, using the
Playwright version bundled with the global CLI. Only system dependencies are
installed as root. Browser binaries are retained when download caches are
cleaned. Images built before this correction need a rebuild and their
sandboxes need recreation before the preinstalled browser is usable.

All harness verification scripts call `shared/verify-toolchain.sh` for common
tools and version checks, then check their agent-specific integrations and
skills. To additionally launch Chromium and exercise a local page without
network access, run inside a sandbox:

```bash
make -C /path/to/sandboxes verify-browser
```

Or from the host:

```bash
sbx exec <sandbox-name> bash /path/to/sandboxes/shared/verify-browser.sh
```

Custom images still use the rebuild commands below; the tracked kits declare
their image and setup behavior for native `sbx create`.

Recreate old sandboxes once for this migration: inspect names with `sbx ls`,
remove a selected old instance with `sbx rm <sandbox-name>`, then run its
launcher again. This loses sandbox sessions/configuration but leaves mounted
repository files intact. Rebuild the Claude template if its image predates this
migration so the baked plugin bootstrap is present; unchanged toolchain images
for the other harnesses can be reused.
Environment/kit changes are creation-time settings, not patches to an existing
instance. There are no bootstrap markers or automatic bootstrap retries on
reattach; after a failed first bootstrap, correct the cause and recreate, or
run the idempotent bootstrap explicitly with `sbx exec`.

## Shared skills

The first launcher run installs Superpowers and Playwright CLI through
`sbx skills add`. Caveman v2.2.0 is checked against commit
`9aa63945a349bef17206540650db48c30fafbdf2` and copied into the same store,
because the native command cannot pin that Git revision. Source checkouts and
backups stay in the host cache, outside the skills store.

```bash
./bin/sbx-skills          # ensure the required skills exist; list the store
./bin/sbx-skills --update # refresh Superpowers/Playwright; keep Caveman pinned
sbx skills ls --json     # includes the native store's actual host path
```

All launchers pass `--skills=readonly`. SBX supplies each agent's native
discovery path; the kits and bootstraps do not manually mount or symlink the
host store. A skill change affects every newly created sandbox; remove and
recreate a sandbox after changing its kit or skills settings, and reload/restart
the agent if it caches skills. Claude plugins remain installed separately
because they provide hooks and integrations beyond skills. Use
`sbx-skills --update`, not a blanket native update, to retain the Caveman pin.

### Other 0.43.0 behavior

Published ports now default to IPv4. Use `--publish 3000:3000/tcp` explicitly
for IPv4 and IPv6. New sandbox Docker volumes default to 10 GB; set
`DOCKER_SANDBOXES_DOCKER_SIZE=20g` before the first launch if more is needed.
That variable does not resize an existing volume.

## Build the harness templates

From this repository, build one or more templates:

```bash
./bin/claude-sbx-rebuild
./bin/codex-sbx-rebuild
./bin/opencode-sbx-rebuild
./bin/agy-sbx-rebuild
./bin/junie-sbx-rebuild
```

These commands pull the current agent base image, build `claude-sbx:local`,
`codex-sbx:local`, `opencode-sbx:local`, `agy-sbx:local`, and `junie-sbx:local`, export
their images under `.build/`, and load them into Docker Sandboxes.
`make rebuild` rebuilds all five templates in sequence. Use
`make rebuild-claude`, `make rebuild-codex`, `make rebuild-opencode`,
`make rebuild-agy`, or `make rebuild-junie` when choosing a single harness. The
Antigravity and Junie builds use the neutral shell base image; Antigravity
contains a pinned CLI release and Junie installs its CLI during bootstrap.

## Put commands on PATH

From this repository:

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

grep -q 'HOME/.local/bin' "$HOME/.zshrc" || \
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
```

## Claude local kit

`claude-sbx` creates a sandbox directly from
`harnesses/claude-code/kit/` with the target repository as its workspace and
native read-only skills access. It then attaches with `sbx run --name`,
forwarding Claude arguments unchanged. No `~/.sbxenv.yaml` file is needed.

`sbx env` is a separate workflow: its `agent` value is resolved as an agent
identifier, not a local v2 kit path, and skills access belongs under
`sandboxOptions.skills`, not at the file root. See Docker's
[environment-file reference](https://docs.docker.com/ai/sandboxes/configuration/environment-files/).

If you use `sbx env` separately and want user-level defaults, an optional
`~/.sbxenv.yaml` could look like this:

```yaml
schemaVersion: "1"
agent: claude
workspace: ${{ env.projectDir }}
sandboxOptions:
  skills: readonly
```

This selects the built-in Claude agent for generic `sbx env` commands. It does
not select this repository's local v2 kit; `claude-sbx` passes that kit directly
to `sbx create` and does not read the file.

The kit and native skills settings are applied when the sandbox is created. If
either changes, remove the affected sandbox with `sbx rm <sandbox-name>` and
run `claude-sbx` again.

## Migrate MCP OAuth secrets

SBX 0.43.0 no longer reads the old `mcp:<server>.client_secret` name. Re-set
each secret under the new name; do not inspect or migrate the secret value in
this repository:

```bash
sbx secret set mcp:<server>:client_secret
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
./bin/agy-sbx-rebuild

# In the target Git repository
cd /path/to/target-repository
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
agy-sbx
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

The Antigravity bootstrap configures `toolPermission` and
`artifactReviewPolicy` as `always-proceed`, so the agent does not repeatedly
ask for tool or artifact approvals inside the isolated sandbox.

Do not put Google credentials in this repository, image, kit, or Antigravity
config files.

## First start: Junie

Build the Junie template before creating its sandbox. Junie CLI authentication
is handled interactively or with a Junie API key:

```bash
# In the harness repository
sbx login
./bin/junie-sbx-rebuild

# In the target Git repository
cd /path/to/target-repository
grep -qxF '.worktrees/' .gitignore || echo '.worktrees/' >> .gitignore
junie-sbx
```

For headless use, keep the key outside the repository and export it only for
the launch. The wrapper passes it as a process environment variable inside the
sandbox and supplies the auth flag there:

```bash
export JUNIE_API_KEY="..."
junie-sbx
unset JUNIE_API_KEY
```

Junie bootstrap enables Brave mode in `~/.junie/config.json` and registers
Serena and Context7 in `~/.junie/mcp/mcp.json`. SBX's native
`--skills=readonly` mode supplies Junie's skills discovery directory; the
bootstrap does not link or populate a host skills store. This disables approval
prompts, including for terminal commands, file access, and MCP tools. The target
repository is mounted read/write, so use this only when you explicitly want
unattended changes; the bootstrap intentionally restores Brave mode on each run.
Do not put Junie credentials, MCP configuration, or session state in the image
or repository.

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
agy-sbx
```

Start Junie:

```bash
junie-sbx
```

All harnesses use direct workspace mode: the target repository is mounted
read/write at its original absolute path. They intentionally do not use
`--clone`. For the direct non-Claude launchers, when the target differs from
this repository, the harness source is also mounted read-only for bootstrap and
verification. If the target is under this repository's `.worktrees/`, only
`harnesses/` and `shared/` are mounted read-only to avoid overlapping mounts.
Claude's bootstrap is baked into its image, so its environment does not mount
this harness checkout. The `.worktrees/` guard is unchanged and exits before
sandbox creation when the directory is not ignored by Git. Use
`sbx inspect <sandbox-name>` to inspect the resulting mounts.

Sandbox names are deterministic but separate:

| Harness | Name | Template |
| --- | --- | --- |
| Claude Code | `claude-<repo-slug>-<8-hex-path-digest>` | `claude-sbx:local` |
| Codex | `codex-<repo-slug>-<8-hex-path-digest>` | `codex-sbx:local` |
| OpenCode | `opencode-<repo-slug>-<8-hex-path-digest>` | `opencode-sbx:local` |
| Antigravity CLI | `agy-<repo-slug>-<8-hex-path-digest>` | `agy-sbx:local` |
| Junie | `junie-<repo-slug>-<8-hex-path-digest>` | `junie-sbx:local` |

Running a command again reuses that harness's deterministic sandbox. Claude
reapplies its named environment before attachment; Codex, OpenCode, Antigravity,
and Junie reuse their native kit configuration. The five harnesses never share
an agent-managed configuration directory or sandbox identity.

## Authentication

Authentication is not baked into any image.

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

For Junie, pass `--auth="$JUNIE_API_KEY"` or
`--auth-license="$JUNIE_LICENSE_KEY"` at runtime. Keep credentials outside the
repository and image.

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
deterministic name, then run the matching verification script for a direct
launcher. Claude's environment intentionally does not mount the harness
checkout; use `sbx inspect <sandbox-name>` for its workspace/native-skills
mounts, and run its verification script when the mounted target is this
checkout:

```bash
source /path/to/claude-sbx/bin/claude-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx inspect "$name"
sbx exec "$name" bash harnesses/claude-code/scripts/verify.sh
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
source /path/to/claude-sbx/bin/agy-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash /path/to/claude-sbx/harnesses/antigravity-cli/scripts/verify.sh
```

For Junie:

```bash
source /path/to/claude-sbx/bin/junie-sbx
repo_root="$(git rev-parse --show-toplevel)"
name="$(sandbox_name_for_repo "$repo_root")"
sbx exec "$name" bash /path/to/claude-sbx/harnesses/junie/scripts/verify.sh
```

Each verification checks its agent CLI plus the shared toolchain, pinned
Node/Go versions, Serena, Playwright CLI, OpenJDK 25, Maven, Gradle, and Docker
Compose. Bootstraps preserve Serena/Context7 MCP registration. SBX's native
read-only skills mode supplies the actual shared `SKILL.md` files at each
agent's discovery path, and verification checks those files rather than the
old per-agent Git checkout layout. Kits instruct agents to use `playwright-cli`
for browser and frontend validation.

## Ports

After a sandbox is created, publish a development port using its name:

```bash
sbx ports <sandbox-name> --publish 3000:3000
```

Use a different port mapping as needed for application servers.

## Rebuild and recreate

Existing sandboxes retain their current VM state and template. After changing a
Dockerfile or shared toolchain script:

1. Rebuild the appropriate template with `claude-sbx-rebuild`,
    `codex-sbx-rebuild`, `agy-sbx-rebuild`, `junie-sbx-rebuild`,
    `make rebuild-opencode`, `make rebuild-agy`, or `make rebuild-junie`.
2. Remove that harness's existing sandbox with `sbx rm <sandbox-name>`.
3. Run the matching harness command again from the target repository.

Kit changes require recreation to apply the complete updated kit, but do not
require rebuilding the image. Native skills settings and Claude environment
changes likewise require removing and recreating the affected sandbox. For an
additive network permission, use the scoped policy command below to update an
existing sandbox immediately.

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
| `template 'claude-sbx:local'`, `template 'codex-sbx:local'`, `template 'opencode-sbx:local'`, or `template 'agy-sbx:local'` is not loaded | In this harness repository, run the matching rebuild command, including `make rebuild-opencode` for OpenCode or `make rebuild-agy` for Antigravity CLI, then try again. |
| `.worktrees/ is not ignored by Git` | In the target repository, add `.worktrees/` to `.gitignore`, review the resulting Git change, then run the harness again. |

If bootstrap or authentication needs network access that the kit does not
allow, inspect the policy log:

```bash
sbx policy log <sandbox-name>
```

`bin/sbx-policy-audit` in this repository automates that review: for every
sandbox, or one named sandbox, it reports blocked domains, whether each is
already in the matching harness kit, and prints ready `sbx policy allow`
commands together with the kit file to update.

Add only the required domain to the appropriate harness kit for future
sandboxes. To unblock an existing sandbox without losing its login or session,
also apply the exact domain to its local policy:

```bash
sbx policy allow network --sandbox <sandbox-name> api.example.com
```

This adds an allow rule for that sandbox only. Removing a domain from a kit
does not remove an existing local policy rule. Find its ID with
`sbx policy ls --wide`, inspect it with `sbx policy inspect <rule-id>`, and
remove it with `sbx policy rm network --sandbox <sandbox-name> --id <rule-id>`
when tightening policy.

Claude bootstrap is idempotent and installs its plugins; Codex
bootstrap is also idempotent and registers Serena and Context7 when their MCP
entries are missing or invalid.

For Junie, HTTP 502 while submitting a prompt can result from a blocked
inference gateway. Check the policy log for
`ingrazzio-cloud-prod.labs.jb.gg:443`. The Junie kit allows that gateway and
`resources.jetbrains.com`, with `oauth.account.jetbrains.com` for account login.
Apply missing domains to an older sandbox with the scoped policy command above.
A blocked `oraios-software.de` request belongs to Serena's
usage reporting or dashboard news, not Junie inference, and does not require
an allow rule to fix this issue.

Junie ships its own Java runtime. The launcher uses the system Java trust store
(`/etc/ssl/certs/java/cacerts`) so Junie trusts the Docker Sandboxes proxy CA.
If JetBrains Account login reports a secure connection failure, launch with
`junie-sbx` rather than invoking the bundled Junie executable directly. This
launcher change applies to existing sandboxes without rebuilding or recreation.

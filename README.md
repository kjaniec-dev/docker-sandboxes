# Docker Sandboxes — SBX V3

Development environments for Docker Sandboxes and Sandbox Kit **V3**.

The enforced version floor lives in [the version check](bin/check-sbx-version.py).
Installed CLI updates do not refresh existing sandbox trust stores or pinned kit images;
follow the [CA maintenance guide](docs/ca-maintenance.md).

Personal: Claude Code, Codex, OpenCode, Antigravity and Junie.
Client: Claude Code through Vertex AI and GitHub Copilot CLI.

Official Docker workloads or agent mixins own launch, authentication and provider network policy.
One shared `mixins/dev` supplies developer tools, instructions and developer network policy.
Declarative `env/` files select the composition. Public commands are symlinks to `bin/sbx-dev`.

## Machine setup

Install SBX and reusable skills with native commands:

The host launcher also requires Git and Python 3.11+ for the shared structured version check.

```bash
brew install docker/tap/sbx
sbx version
sbx skills add https://github.com/obra/superpowers.git --force
sbx skills add https://github.com/microsoft/playwright-cli.git --skill playwright-cli --force
sbx skills add https://github.com/JuliusBrussee/caveman.git --skill caveman --force
sbx skills ls
```

Update skills with `sbx skills update`. They remain in the native shared store and are exposed
read-only at each agent's skills path.

The launcher and validation default `SBX_KIT_BUILDER=sandbox`, preserving an explicit override.
Native SBX builds local source kits and caches them in its builder sandbox. Provision a builder
with 16 GiB of memory and a 64 GiB engine-store volume for the shared toolchain. If the default
builder runs out of space or is killed during compilation, use native
`sbx kit builder rm --force` to remove its regenerable cache, then provision the official builder:

```bash
sbx create --name sbx-kit-builder --memory 16g --kit-arg volumeSize=64g docker/sbx-kit-builder:1
```

Install command aliases from this checkout:

```bash
mkdir -p "$HOME/.local/bin"
for command in claude-sbx codex-sbx opencode-sbx agy-sbx junie-sbx copilot-sbx; do
  ln -sfn "$PWD/bin/$command" "$HOME/.local/bin/$command"
done
```

## Client profile setup (Vertex Claude)

Client Claude needs a few host inputs before the first launch. Without them `claude-sbx` stops at
the first missing one. Do this once per machine, in order:

```bash
# 1. Host-only Google credentials; never copied into a sandbox.
gcloud auth application-default login

# 2. Profile and Vertex settings for every new shell (use your approved project and region).
cat >> ~/.zshrc <<'EOF'
export SBX_PROFILE=client
export ANTHROPIC_VERTEX_PROJECT_ID='<approved-project>'
export CLOUD_ML_REGION='<approved-region>'   # for example eu
EOF
source ~/.zshrc

# 3. Machine-local overlay from the template, with your gcloud and home paths filled in.
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/docker-sandboxes"; mkdir -p "$cfg"
[ -e "$cfg/client.sbxenv.yaml" ] || sed -e "s#/Users/YOUR_USER#$HOME#" \
  -e "s#/opt/homebrew/bin/gcloud#$(command -v gcloud)#" \
  env/client/client.sbxenv.yaml.example > "$cfg/client.sbxenv.yaml"
```

Then launch `claude-sbx` from a project checkout and approve the plan, which includes a host
command. The overlay stays outside the repository because that command runs on your host and
must not live where a sandbox can modify it. Adjust the Vertex hosts in the overlay to your
approved regions; see [client Vertex configuration](docs/client-vertex.md).

## Launch an agent

Run inside the project's main Git checkout. Add `.worktrees/` to its Git ignore rules first.

The launcher audits local Git configuration and hooks before launch and on exit. This detects
command-bearing metadata but does not isolate writable `.git` from concurrent host Git or shell
prompts. Read [the Git metadata policy and recovery steps](docs/git-metadata.md) before use; keep
this launcher checkout outside workspaces exposed to untrusted agents.

```bash
cd ~/src/my-project
codex-sbx
claude-sbx
opencode-sbx
agy-sbx
junie-sbx
```

All agent arguments pass through as individual arguments. Junie defaults to `--brave`;
an explicit `--no-brave` overrides it. OpenCode defaults to `--auto` and the OpenCode Go provider;
an explicit `--no-auto` overrides the launch default.

Sandbox names combine profile, agent, repository basename and a digest of the absolute repository
path. Repeated launches reuse the same sandbox. The launcher rejects tracked or symlinked
`.worktrees/`, unignored worktrees, and linked checkouts whose Git metadata falls outside the
single mounted project. Launch from the main checkout and let the agent create worktrees underneath it.
Names and grouping depth inside `.worktrees/` are unrestricted. Independent repositories there are
supported too, with the same Git metadata checks as the main checkout.

Select a profile using `SBX_PROFILE` or a `profile` file in
`${XDG_CONFIG_HOME:-$HOME/.config}/docker-sandboxes`. The default is `personal`.
A machine-local `personal.sbxenv.yaml` or `client.sbxenv.yaml` in that directory merges after the
committed agent and common environments.

```bash
SBX_PROFILE=client copilot-sbx
SBX_PROFILE=client claude-sbx
```

Client Claude requires the host inputs in [Client profile setup](#client-profile-setup-vertex-claude);
see [client Vertex configuration](docs/client-vertex.md) for credential visibility and runtime
verification.
Client Claude uses host-only token resolution and a sandbox-scoped native placeholder; ADC is not
mounted. The flow applies only to client Claude, not personal agents or client Copilot.

## Native lifecycle and authentication

SBX owns credentials, sandbox creation, stop/start, removal and kit composition. Configure
credentials and authorize their agent bindings using native SBX setup. A stored credential without
an authorized binding is not injected. Junie's current backend is missing from the official kit's
credential domains. With a real Junie CLI token temporarily exported as `JUNIE_API_KEY` in your
host terminal, store it using native custom-secret substitution for both provider hosts:

```bash
sbx secret set-custom \
  --host junie.jetbrains.com \
  --host ingrazzio-cloud-prod.labs.jb.gg \
  --env JUNIE_API_KEY \
  --value "$JUNIE_API_KEY"
unset JUNIE_API_KEY
junie-sbx
```

The custom secret is global and survives sandbox removal; the real token stays on the host.
The official workload masks the generated custom placeholder with `proxy-managed`. A small
Junie-only adapter selects the public placeholder from native secret metadata, preferring sandbox
scope over global scope, and passes it with native `sbx env exec --env`. It never retrieves the
token. This bridges the demonstrated masking behavior without replacing native secret storage.
Junie's official workload remains in use. Its small declaration-only extension supplies the missing
provider domain, while native JVM proxy options let its MCP client reach the SBX gateway.

`sbx env run` starts an existing sandbox without re-provisioning it. Kit and policy edits apply
when it is recreated. Junie and client Claude use `sbx env exec` to apply current environment variables
to each new session. Client Claude preserves its thin workload's `--dangerously-skip-permissions`
launch default. Other launchers' subsequent plain `sbx run --name` uses the existing container's
environment, so recreate those containers to apply changed defaults. Use native `sbx env rm`
with the same files, name and arguments
shown by the launcher, then launch again. Removing a sandbox loses its sandbox-local session state;
the bind-mounted project remains on the host.

Existing pre-rewrite sandboxes also require recreation to receive this composition. Their automatic
migration or deletion is not part of the launcher.

## MCP and instructions

`env/common.sbxenv.yaml` declares Context7 once through the native SBX MCP gateway:

```yaml
mcp:
  servers:
    - name: context7
      url: https://mcp.context7.com/mcp
```

In Codex, `/mcp` lists the shared endpoint as `mcp-gateway`. Context7 is exposed through it,
with tools such as `resolve-library-id` and `query-docs`, rather than as a separate MCP server entry.

Register other remote or host servers with native commands:

```bash
sbx mcp add notion --url https://mcp.notion.com/mcp
sbx mcp load notion --sandbox <sandbox-name>
sbx mcp ls
```

For a trusted Unity MCP loopback endpoint:

```bash
sbx mcp add unity --url http://127.0.0.1:8080/mcp --skip-ssrf-check
sbx mcp load unity --sandbox <sandbox-name>
```

Serena runs inside the sandbox as a local stdio MCP server against the mounted project.
Do not register it as a host `sbx mcp --command` server.
`mixins/dev/configure-agent.py` preserves unrelated agent settings while registering Serena.
It supplies Junie's missing gateway registration. Native `agent-context.directory` places Claude
and Codex instructions in their agent homes; no Codex instruction symlink is needed.
Official kits register the gateway for the other agents.
Their OpenCode/Antigravity `jq` merge can erase malformed MCP maps. The shared jq launcher validates
those configuration paths whenever they appear in its arguments, including relative paths and
symlinks, independently of options and filter spelling. Native smoke executes the installed official
gateway hook against malformed fixtures to detect changes that bypass file arguments.

Common instructions use native `agent-context`. A retained install hook restores Antigravity's
config-directory ownership. See the [workaround register](docs/workarounds.md) for the original
observations, current evidence limits, removal conditions and probes for these integration adapters.

## Developer tools and composition

The shared mixin supplies Java 25, Maven, Gradle, Python/uv, Serena, Go development utilities,
pnpm/corepack, Playwright CLI/Chromium, and shell/search/database tools.
It exports tools and their scoped dependencies without replacing the workload's operating system,
Node or Go runtimes. A broken workload uv/uvx is replaced with the baked working binary only when its
version probe fails.

Ripgrep comes from each workload's base image (`/usr/bin/rg`); the shared mixin does not
install or export another copy. Claude uses its default built-in search configuration.

Claude and OpenCode retain thin local workloads after standalone workload-name collisions observed
during the original cutover. Official agent mixins supply their binaries, credentials, provider egress
and gateway hooks. Retirement requires the [clean replacement probes](docs/workarounds.md),
including testing the current supported SBX release. Podman Desktop needs no custom backend integration.

The [environment files](env/) are authoritative for official kit digests and their selection comments;
[cutover evidence](docs/cutover.md) records the versions and runtime matrix actually tested.
A digest pins the published artifact; agent CLIs may still self-update. Docker's `latest` channel
can lag numbered releases, and numbered tags can be rebuilt with another digest.
Update a pin only after the replacement passes `tests/validate.sh` and that agent's smoke test.
Do not patch or copy official descriptors to remove unknown fields. Existing sandboxes require
recreation to receive updated kits; raising the CLI minimum or editing a pin does not update them.

## Verification

Host prerequisites for validation: Git, Python 3.11+ and jq; native checks also require supported SBX,
a running daemon and Docker sign-in. The repository's `--offline` mode runs behavioral tests without
requiring SBX and skips native builds and runtime checks. Although SBX 0.49.1 adds `kit inspect --offline`
and `kit validate --offline`, both reject this repository's V3 source kits because the offline load path
has no kit builder configured, including for kits without a Dockerfile. Use full native validation for
these kits. See [migration evidence](docs/cutover.md#sbx-0491-migration-2026-10-21).
GitHub Actions runs ShellCheck, Ruff correctness checks and offline behavior validation on every
pull request and push to `main`.

```bash
./tests/validate.sh --offline  # launcher/config/model-response/ignore behavior; no SBX required
./tests/validate.sh           # also native source kit builds and all seven environment plans
./tests/smoke.sh codex        # real tools, Chromium, skills, context, Serena and Context7
SBX_SMOKE_MODEL=1 ./tests/smoke.sh codex  # also completed authenticated model responses
SBX_PROFILE=client ./tests/smoke.sh copilot

# Full infrastructure/lifecycle matrix on a supported SBX release.
for agent in claude codex opencode antigravity junie; do
  SBX_PROFILE=personal ./tests/smoke.sh "$agent" || break
done
for agent in claude copilot; do
  SBX_PROFILE=client ./tests/smoke.sh "$agent" || break
done
```

Smoke tests create uniquely named disposable repositories and sandboxes, test fresh launch,
stop/start and delete/recreate, then remove their sandbox and workspace. At each stage, Git must
preserve ignore decisions for `.worktrees/` and an existing fixture ignored only by host `.git/info/exclude`.
A marker in the agent's sandbox-local home must survive stop/start and disappear after delete/recreate.
Logs remain at the printed location. A failed model request cannot count as a passing result.
Default smoke results explicitly
say authentication was not checked. `SBX_SMOKE_KEEP_ON_FAILURE=1` retains a failed test sandbox for
diagnosis when native SBX has not already removed it.

See [cutover evidence](docs/cutover.md) for the tested matrix and remaining authentication checks.

There are no harness directories, template tar exports, per-agent rebuild commands or compatibility
layers. Git history is the archive. Add an agent through an official workload, an environment file
and the launcher matrix; keep shared behavior in `mixins/dev`.

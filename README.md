# Docker Sandboxes — SBX V3

Development environments for Docker Sandboxes **0.46.0+** and Sandbox Kit **V3**.

Personal: Claude Code, Codex, OpenCode, Antigravity and Junie.
Client: Claude Code through Vertex AI and GitHub Copilot CLI.

Official Docker workloads or agent mixins own launch, authentication and provider network policy.
One shared `mixins/dev` supplies developer tools, instructions and developer network policy.
Declarative `env/` files select the composition. Public commands are symlinks to `bin/sbx-dev`.

## Machine setup

Install SBX and reusable skills with native commands:

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
Native SBX builds local source kits and caches them in its builder sandbox. This toolchain was
validated with a 32 GiB builder volume. If the default builder runs out of space, use native
`sbx kit builder rm --force` to remove its regenerable cache, then provision the official builder:

```bash
sbx create --name sbx-kit-builder --kit-arg volumeSize=32g docker/sbx-kit-builder:1
```

Install command aliases from this checkout:

```bash
mkdir -p "$HOME/.local/bin"
for command in claude-sbx codex-sbx opencode-sbx agy-sbx junie-sbx copilot-sbx; do
  ln -sfn "$PWD/bin/$command" "$HOME/.local/bin/$command"
done
```

## Launch an agent

Run inside the project's main Git checkout. Add `.worktrees/` to its Git ignore rules first.

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

Select a profile using `SBX_PROFILE` or a `profile` file in
`${XDG_CONFIG_HOME:-$HOME/.config}/docker-sandboxes`. The default is `personal`.
A machine-local `personal.sbxenv.yaml` or `client.sbxenv.yaml` in that directory merges after the
committed agent and common environments.

```bash
SBX_PROFILE=client copilot-sbx
SBX_PROFILE=client claude-sbx
```

Client Claude requires host `ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION`.
Keep its approved ADC/WIF or host-only secret-proxy settings in the machine-local overlay; see
[client Vertex configuration](docs/client-vertex.md) for credential visibility and runtime verification.
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
It supplies Junie's missing gateway registration and bridges native context into Codex's global
instruction discovery. Official kits register the gateway for the other agents.
Their OpenCode/Antigravity `jq` merge can erase malformed MCP maps. The shared jq launcher checks
only that merge against those two configuration paths and rejects it before a destructive write.

Common instructions use native `agent-context`. SBX 0.46 creates Antigravity's skills ancestors
as root-owned directories; a small native install hook restores their agent ownership so official
startup hooks can write configuration.

## Developer tools and composition

The shared mixin supplies Java 25, Maven, Gradle, Python/uv, Serena, Go development utilities,
pnpm/corepack, Playwright CLI/Chromium, and shell/search/database tools.
It exports tools and their scoped dependencies without replacing the workload's operating system,
Node or Go runtimes. A broken workload uv/uvx is replaced with the baked working binary only when its
version probe fails.

Claude and OpenCode use thin local workloads because their official standalone workload names
collide with SBX 0.46 built-ins. Official agent mixins still supply their binaries, credentials,
provider egress and gateway hooks. Prefer the official standalone workloads once that collision
is resolved. Podman Desktop needs no custom SBX backend integration.

Both Claude profiles pin the official Claude 2.1.285 mixin by digest. The `latest` kit published
on 2026-10-06 adds `agent-context.directory`, which SBX 0.46.0 and 0.47.0 reject as an unknown field.
Update the pin only after the replacement passes native validation and the Claude smoke test
on the supported SBX version.

## Verification

Host prerequisites for validation: Git, Python 3.11+ and jq; native checks also require SBX.

```bash
./tests/validate.sh --offline  # launcher/config/model-response behavior
./tests/validate.sh           # also native source kit builds and all seven environment plans
./tests/smoke.sh codex        # real tools, Chromium, skills, context, Serena and Context7
SBX_SMOKE_MODEL=1 ./tests/smoke.sh codex  # also completed authenticated model responses
SBX_PROFILE=client ./tests/smoke.sh copilot
```

Smoke tests create uniquely named disposable repositories and sandboxes, test fresh launch,
stop/start and delete/recreate, then remove their sandbox and workspace. Logs remain at the printed
location. A failed model request cannot count as a passing result. Default smoke results explicitly
say authentication was not checked. `SBX_SMOKE_KEEP_ON_FAILURE=1` retains a failed test sandbox for
diagnosis when native SBX has not already removed it.

See [cutover evidence](docs/cutover.md) for the tested matrix and remaining authentication checks.

There are no harness directories, template tar exports, per-agent rebuild commands or compatibility
layers. Git history is the archive. Add an agent through an official workload, an environment file
and the launcher matrix; keep shared behavior in `mixins/dev`.

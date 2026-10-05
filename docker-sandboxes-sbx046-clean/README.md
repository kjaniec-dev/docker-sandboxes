# Docker Sandboxes — clean SBX 0.46 setup

A small, opinionated development environment for Docker Sandboxes **0.46+**.

The design deliberately delegates as much as possible to native SBX features:

- **agents** → official V3 workloads or official V3 agent mixins,
- **development tooling** → one local `dev` mixin,
- **skills** → native `sbx skills` shared store,
- **remote MCP servers** → native `sbx mcp` / MCP gateway via `sbxenv.yaml`,
- **instructions** → V3 `agent-context`,
- **credentials** → SBX credentials/secrets and official agent kits,
- **runtime configuration** → declarative `sbx env`,
- **launching** → one tiny `bin/sbx-dev` entrypoint.

There is intentionally no V2 compatibility layer, template tar workflow, per-agent rebuild script,
`harness_root`, infrastructure-repository mount, or generated per-agent shell framework.

## Profiles

### Personal

- Claude Code
- Codex
- OpenCode
- Antigravity
- Junie

### Client

- Claude Code via Vertex AI
- GitHub Copilot CLI

The client machine may use **Podman Desktop** instead of Docker Desktop. That does not change this
layout: SBX has its own sandbox runtime and does not use Podman Desktop as its backend.

## Repository shape

```text
.
├── bin/
│   └── sbx-dev
├── env/
│   ├── common.sbxenv.yaml
│   ├── personal/
│   └── client/
├── mixins/
│   ├── dev/
│   └── vertex/
├── workloads/
│   ├── claude-dev/
│   └── opencode-dev/
├── tests/
│   ├── validate.sh
│   └── smoke.sh
└── docs/
```

The public commands (`claude-sbx`, `codex-sbx`, etc.) are symlinks to the same `sbx-dev` launcher.

## 1. Install SBX

```bash
brew install docker/tap/sbx
sbx version
```

This repository targets **SBX 0.46.0 or newer** and Sandbox Kit V3.

## 2. Install shared skills once per machine

Keep skills outside this repository and let SBX mount them read-only into agent skill directories.

```bash
sbx skills add https://github.com/obra/superpowers.git --force
sbx skills add https://github.com/microsoft/playwright-cli.git --skill playwright-cli --force
sbx skills add https://github.com/JuliusBrussee/caveman.git --skill caveman --force

sbx skills ls
```

Update them with native SBX commands:

```bash
sbx skills update
```

No custom `skills.sh`, symlink farm, or per-agent skills bootstrap is used.

> The previous repository pinned Caveman manually because `sbx skills add` does not pin a Git ref.
> This clean version deliberately prefers the native lifecycle. If a strict pin becomes important,
> publish/version that skill separately rather than bringing the old shared-skills framework back.

## 3. MCP

`env/common.sbxenv.yaml` registers **Context7** with the native MCP gateway:

```yaml
mcp:
  servers:
    - name: context7
      url: https://mcp.context7.com/mcp
```

Add other remote MCP servers once on the host:

```bash
sbx mcp add notion --url https://mcp.notion.com/mcp
sbx mcp ls
```

Attach an already-registered server to a running sandbox without restarting the agent:

```bash
sbx mcp load notion --sandbox <sandbox-name>
```

### Unity MCP

If Unity MCP listens on the trusted host loopback endpoint, register it on the host:

```bash
sbx mcp add unity --url http://127.0.0.1:8080/mcp --skip-ssrf-check
sbx mcp load unity --sandbox <sandbox-name>
```

This is preferable to putting `host.docker.internal` into every agent's own MCP config. The agent
sees the SBX gateway; the gateway talks to Unity on the host.

### Serena is the intentional exception

Do **not** register Serena with `sbx mcp add --command serena ...`: local stdio MCP commands registered
that way run on the **host**, outside sandbox isolation. `mixins/dev/configure-agent.py` registers the
Serena stdio server inside each sandbox against its mounted project. This is the one small adapter
kept because it protects the isolation model.

## 4. Install command aliases

From this repository:

```bash
mkdir -p "$HOME/.local/bin"
for command in claude-sbx codex-sbx opencode-sbx agy-sbx junie-sbx copilot-sbx; do
  ln -sfn "$PWD/bin/$command" "$HOME/.local/bin/$command"
done
```

The committed files in `bin/` are symlinks to `sbx-dev`, so all behavior lives in one launcher.

## 5. Personal usage

Default profile is `personal`:

```bash
cd ~/src/my-project
codex-sbx
claude-sbx
opencode-sbx
agy-sbx
junie-sbx
```

You can make it explicit:

```bash
export SBX_PROFILE=personal
```

The launcher:

1. finds the current Git root,
2. requires `.worktrees/` to be ignored,
3. computes a deterministic sandbox name from agent + repository path,
4. applies the selected `sbxenv.yaml` + common environment,
5. starts/reattaches the sandbox.

## 6. Client usage

On the client machine:

```bash
export SBX_PROFILE=client
```

Then:

```bash
claude-sbx
copilot-sbx
```

Client Claude requires the Vertex project and region on the host:

```bash
export ANTHROPIC_VERTEX_PROJECT_ID='my-gcp-project'
export CLOUD_ML_REGION='us-east5'   # use the region approved for your client
claude-sbx
```

`CLAUDE_CODE_USE_VERTEX=1` is declared by `env/client/claude.sbxenv.yaml`.

### Vertex authentication

This repository intentionally does **not** copy `~/.config/gcloud`, a service-account key, or other
client credentials into Git. Keep the client's existing working ADC/WIF mechanism.

If that mechanism needs machine-specific SBX declarations, create:

```text
~/.config/docker-sandboxes/client.sbxenv.yaml
```

`sbx-dev` automatically merges that file for the client profile. This is the only intended place for
client-machine-specific mounts/environment declarations. Keep it outside this repository.

See `docs/client-vertex.md`.

## 7. Common development environment

`mixins/dev` owns shared development behavior:

- Java 25 + Maven + Gradle,
- Python + `uv`,
- Serena,
- Go language/dev tooling,
- pnpm,
- Playwright CLI + Chromium,
- shell/search/database utilities,
- common developer network allow-list,
- common agent instructions,
- the small agent-local Serena MCP adapter.

Node, Go, Git, Docker/Compose and other core tooling already supplied by official sandbox templates are
not needlessly reinstalled unless the mixin actually requires an addition.

Project-local wrappers and versions always win over globally installed convenience tools.

## 8. Why Claude and OpenCode have tiny local workloads

Docker currently publishes V3 `claude` and `opencode` workloads, but SBX 0.46 still has built-in
agents with those names, so the published workloads collide with the built-ins.

Instead of forking Docker's complete agent implementations, this repository uses:

```text
local claude-dev shell workload
  + docker/sbx-kit-claude-mixin
  + local dev mixin

local opencode-dev shell workload
  + docker/sbx-kit-opencode-mixin
  + local dev mixin
```

The official mixins own the agent binary, auth, agent-specific egress and MCP-gateway integration.
Our workloads own only the launch command, context profile and skills destination.

When SBX removes the old built-in name collision, delete these two local workloads and use the
official standalone workloads directly.

## 9. Validation

Fast structural/native checks:

```bash
./tests/validate.sh
```

Real sandbox smoke tests are opt-in because they create/delete sandboxes and may require credentials:

```bash
./tests/smoke.sh codex
./tests/smoke.sh claude
```

Client examples:

```bash
SBX_PROFILE=client ./tests/smoke.sh copilot
SBX_PROFILE=client ./tests/smoke.sh claude
```

## 10. Adding another agent

Prefer this order:

1. official Docker V3 workload,
2. official agent mixin + a tiny local workload only if a workload name collision exists,
3. custom workload only when neither option is available.

A new official workload normally needs only one `env/<profile>/<agent>.sbxenv.yaml` file and a
resolver entry in `bin/sbx-dev`.

Do not reintroduce a harness generator unless adding agents actually becomes repetitive again.

## Design rules

- Native SBX feature before custom shell.
- Official agent kit before local copy.
- One shared `dev` mixin before per-agent toolchains.
- `sbx skills` owns reusable skills.
- `sbx mcp` owns remote/host MCP servers.
- Serena stays sandbox-local.
- Workload owns provider-specific auth/egress; `dev` owns common developer egress.
- No V2 compatibility after cutover.
- No infrastructure-repo mount inside sandboxes.
- No `docker build` / `docker image save` / `sbx template load` workflow.
- No per-agent rebuild scripts.
- Behavioral smoke tests over grep-based implementation tests.

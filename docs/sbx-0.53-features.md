# Optional developer features in Docker Sandboxes 0.53

Docker Sandboxes v0.53.0 introduced native disk accounting, Claude in Chrome
and permissionless **ephemeral loopback** port assignment for kits with an
explicit `ports.publish` API grant. The required version floor is added by
[PR #31](https://github.com/kjaniec-dev/docker-sandboxes/pull/31); this feature
PR is stacked on #31 and does **not** enable new permissions by default.

Upstream references:
- [v0.53.0 release notes](https://github.com/docker/sbx-releases/releases/tag/v0.53.0)
- [Kit authoring: publish a development service](https://docs.docker.com/ai/sandboxes/customize/author/patterns/#publish-a-development-service)
- [Claude in Chrome](https://docs.docker.com/ai/sandboxes/agents/claude-code/#claude-in-chrome)
- [Settings reference](https://docs.docker.com/ai/sandboxes/configuration/settings/)

## 1. Disk accounting (no configuration)

```bash
sbx df
sbx df --verbose
```

These are native host commands. Results include images, containers and managed
volumes. The reclaimable estimate is **not** what `sbx prune` alone will free.
No cleanup is performed by either command. Do not automatically prune active
project sandboxes or their volumes.

## 2. Optional ephemeral localhost ports

Default profiles still **do not** have this grant. To create or reuse a
separately named sandbox with the optional grant, run from the main project
checkout:

```bash
SBX_AUTO_PORTS=1 codex-sbx
# or SBX_AUTO_PORTS=1 claude-sbx, etc.
```

This composes `env/features/auto-ports.sbxenv.yaml` after the agent and common
configuration and before any machine-local overlay. The fragment adds the
`mixins/auto-ports` V3 kit, granting
`com.docker.sandbox/api@1 / ports.publish / approval: none`.

The enabled sandbox name ends with `-ports`; the regular sandbox remains
untouched, including its settings, credentials and sandbox-local files. Both
instances mount the **same project checkout**: do not use them concurrently to
edit the same files. The feature does not start or publish a server by itself.

Inside the opted-in sandbox, start a development server on a sandbox port,
for example Next.js on port 3000 (bind to an appropriate interface such as
`0.0.0.0` inside the sandbox). Then request a loopback host binding **from
inside that sandbox**:

```bash
curl --noproxy '*' --max-time 60 --fail-with-body \
  -H 'Content-Type: application/json' \
  --data '[{"sandbox_port":3000}]' \
  "${HTTP_PROXY%/}/_sbx/api/ports"
```

Read `host_ip` and `host_port` from the response; connect to the returned
host-local address and assigned port. Omitting `host_port` makes the
publication ephemeral and loopback-only. Fixed host port assignments still
require manual approval. These bindings disappear when the sandbox stops and
do **not** automatically return after restart. Port 3000 must be listening
before testing connectivity. Never pass an externally accessible host address
or a fixed host port for the no-approval flow.

With `SBX_AUTO_PORTS` unset or `0`, launchers continue to use their original
sandbox names and kit sets. Only `0` and `1` are accepted. To revoke the
published binding, stop the `-ports` sandbox; to return to the original
profile, run the normal launcher without the flag. Removing a sandbox can
destroy its local session files: preserve those first. The working tree stays
on the host.

## 3. Claude in Chrome (separate host-global opt-in)

This is **not** enabled by the repo or the port feature. It grants sandboxed
Claude Code access to Chrome tabs on the host. Confirm your organizational
policy and install/sign in to the Claude in Chrome browser extension. Use a
matching **Claude subscription OAuth login** for Claude Code; an Anthropic API
key or the client Vertex configuration alone is insufficient.

```bash
sbx settings get claude.chrome       # default false
sbx settings set claude.chrome true # explicit host-wide opt-in
claude-sbx --chrome                 # personal Claude with subscription OAuth
```

The setting applies to new browser connections from running Claude sandboxes.
It is not scoped to a single project, and the browser extension can expose
sensitive tab contents to the connected agent. Use only trusted sessions and
do not enable it automatically for the client/Vertex profile. To stop new
connections:

```bash
sbx settings set claude.chrome false
```

Disabling the setting does not terminate established browser connections:
end any active Claude Chrome sessions in the browser too. None of these steps
changes the host OAuth registration for Context7 or SBX model credentials.

## 4. Validation (owner's Mac; never on active project sandboxes)

```bash
sbx version --json
./tests/validate.sh                  # includes port mixin inspection and opt-in plan
SBX_PROFILE=personal ./tests/smoke.sh codex
SBX_AUTO_PORTS=1 SBX_PROFILE=personal ./tests/smoke.sh codex
sbx df
sbx mcp inspect context7
```

Smoke tests use disposable named sandboxes and verify lifecycle and MCP; they
**do not** prove the localhost publication API, Chrome subscription OAuth or
an authenticated model request. Verify the API separately on a disposable
opted-in sandbox with an actual running test server: it should return a
loopback host and dynamic port, become accessible only locally, and disappear
after `sbx stop`. Test Chrome only with approved browser access and matching
subscription credentials. Test the remaining agent/profile matrix from
[PR #31's checklist](upgrade-sbx-0.53.md) before merging.

All native runtime gates are **PENDING**, until recorded by the owner on macOS.
GitHub-hosted offline validation cannot exercise the SBX daemon or kit builder.

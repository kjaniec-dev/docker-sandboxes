# Client Claude through Vertex AI

The client environment composes the same thin Claude workload, official Claude mixin and shared
dev mixin with `mixins/vertex`. The committed configuration declares
`CLAUDE_CODE_USE_VERTEX=1`, required project/region arguments and Vertex runtime network policy.

```bash
export SBX_PROFILE=client
export ANTHROPIC_VERTEX_PROJECT_ID='approved-project'
export CLOUD_ML_REGION='approved-region'
claude-sbx
```

Authentication remains the client's approved ADC/WIF mechanism. Project and region arguments
select Vertex but do not make host credentials visible inside the sandbox. A successful host
`gcloud` login alone is not sufficient.

Keep any required client-machine declarations in
`${XDG_CONFIG_HOME:-$HOME/.config}/docker-sandboxes/client.sbxenv.yaml`.
The launcher merges this native environment overlay after the committed client and common files.
Use the approved sandbox-visible ADC/WIF path as-is; do not replace it with a new credential flow.

## Model-specific regions

Keep the approved default region in `CLOUD_ML_REGION`. If Haiku 4.5 needs `europe-west1` while
other models use the `eu` multi-region endpoint, merge this into the machine-local
`client.sbxenv.yaml`:

```yaml
env:
  VERTEX_REGION_CLAUDE_HAIKU_4_5: europe-west1
```

This overrides only Haiku 4.5, not the default region or other models. A host-only `export`
is not automatically forwarded into the sandbox. The client Claude launcher uses native
`sbx env exec` to apply the merged environment to every new Claude session, including sessions in an
existing sandbox. Exit the running Claude process and relaunch `SBX_PROFILE=client claude-sbx`
to apply a changed override; sandbox recreation is unnecessary.

An HTTP 429 can also mean actual quota or capacity exhaustion. If it persists in the required
region, investigate that project's regional model quota rather than treating retries as a fix.

On 2026-10-06, a completed Haiku 4.5 response was verified through the merged native environment
with `VERTEX_REGION_CLAUDE_HAIKU_4_5=europe-west1` and `CLOUD_ML_REGION=eu`.

## Existing approved user ADC

If the client approves the existing host
`$HOME/.config/gcloud/application_default_credentials.json`, expose only that file read-only.
Do not mount the whole Google Cloud configuration directory or copy credentials into the project.
This uses native `sbx mount` (available on the verified SBX 0.47.0 installation); check
`sbx mount --help` on your installation before using it.

Merge the following into the machine-local `client.sbxenv.yaml`:

```yaml
schemaVersion: "1"

lifecycle:
  postCreate:
    - name: Mount approved Vertex ADC for Claude
      command: |
        if [ "$SBX_AGENT" = claude-dev ]; then
          sbx mount "$SBX_SANDBOX_NAME" \
            "$HOME/.config/gcloud/application_default_credentials.json:/home/agent/.config/gcloud/application_default_credentials.json:ro"
        fi
```

The native host lifecycle supplies `SBX_AGENT` and `SBX_SANDBOX_NAME`. The guard restricts
credential access to client Claude; the shared client overlay does not mount ADC into Copilot.
Host commands require native plan approval on each invocation by default.

The destination is Google's standard ADC path under the sandbox user's home, so
`GOOGLE_APPLICATION_CREDENTIALS` is unnecessary for this layout. Native mounts survive stop/start.
The hook reapplies the mount after sandbox recreation, but does not run for existing sandboxes.
For an existing Claude sandbox, apply the same native mount once without deleting its session:

```bash
sbx ls
sbx mount <client-claude-sandbox-name> \
  "$HOME/.config/gcloud/application_default_credentials.json:/home/agent/.config/gcloud/application_default_credentials.json:ro"
```

Retry the request. If the running Claude process retains an earlier authentication error,
exit and relaunch it. For another approved ADC/WIF layout, use its sandbox-visible path and set
`GOOGLE_APPLICATION_CREDENTIALS` as needed; external-account configurations may also require
their approved credential source. Do not substitute user ADC for a required WIF mechanism.

## Runtime verification

Once the client configuration is available, run:

```bash
SBX_PROFILE=client SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
```

This creates a disposable environment using the same overlay and requires successful tooling, MCP,
skills, Chromium, lifecycle and completed model requests. Its result must be recorded separately from
portable kit and environment-plan validation.

On 2026-10-06, SBX 0.47.0 with the approved existing user ADC passed this full client Claude
smoke at fresh, stop/start and delete/recreate stages, including completed Vertex model responses.
The existing user sandbox also completed a model request. Its ADC mount was confirmed read-only,
and the existing Copilot sandbox had no ADC file. This verifies the user ADC configuration above,
not other client WIF configurations.

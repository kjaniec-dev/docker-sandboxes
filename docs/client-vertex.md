# Client Claude through Vertex AI

The client environment composes the same thin Claude workload, official Claude mixin and shared
dev mixin with `mixins/vertex`. The committed configuration declares
`CLAUDE_CODE_USE_VERTEX=1`, `CLAUDE_CODE_SKIP_VERTEX_AUTH=1`, required project/region arguments
and Vertex-only provider network policy. Authentication stays on the host.

```bash
export SBX_PROFILE=client
export ANTHROPIC_VERTEX_PROJECT_ID='approved-project'
export CLOUD_ML_REGION='approved-region'
claude-sbx
```

Authentication uses the existing approved host ADC through the native secret proxy described below.
Project and region arguments select Vertex but do not authenticate requests by themselves.

Keep any required client-machine declarations in
`${XDG_CONFIG_HOME:-$HOME/.config}/docker-sandboxes/client.sbxenv.yaml`.
The launcher merges this native environment overlay after the committed client and common files.
Use only the approved credential flow. Host-only token injection below reuses the existing host
ADC; it does not introduce a service-account key or a new login.

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

## Host-only ADC through the native secret proxy

This flow is for **client Claude only** and was verified on SBX 0.47.0 with the pinned Claude Code
2.1.285 mixin. Personal Claude and client Copilot do not use it. Keep ADC on the host; do not mount
it, even read-only, into a client Claude sandbox.

The host runs `gcloud auth application-default print-access-token` using its existing approved
ADC. A sandbox-scoped native custom secret substitutes a public placeholder in request headers
only for the configured Vertex hosts. Claude runs with `CLAUDE_CODE_SKIP_VERTEX_AUTH=1` and sends
`ANTHROPIC_AUTH_TOKEN` as `Authorization: Bearer <placeholder>`; it does not read ADC itself.
Neither the ADC refresh token nor the real access token is supplied in the sandbox environment.
The local command is `sbx secret set-custom`, not `sbx secret set custom`. Local substitution does
not use the cloud-only `--header` and `--format` flags.

Replace the old ADC-mount hook in the machine-local `client.sbxenv.yaml` with native secret
registration. The following uses the verified Homebrew gcloud path; adjust the absolute executable
path for your host and keep it outside writable sandbox mounts:

```yaml
schemaVersion: "1"

env:
  VERTEX_REGION_CLAUDE_HAIKU_4_5: europe-west1

lifecycle:
  postCreate:
    - name: Register host-only Vertex authentication for client Claude
      command: |
        if [ "$SBX_AGENT" = claude-dev ]; then
          sbx secret set-custom \
            --sandbox "$SBX_SANDBOX_NAME" \
            --host aiplatform.eu.rep.googleapis.com \
            --host europe-west1-aiplatform.googleapis.com \
            --env ANTHROPIC_AUTH_TOKEN \
            --command "/usr/bin/env CLOUDSDK_CONFIG='$HOME/.config/gcloud' /opt/homebrew/bin/gcloud auth application-default print-access-token" \
            --refresh 45m
          sbx policy deny network --sandbox "$SBX_SANDBOX_NAME" \
            'oauth2.googleapis.com,sts.googleapis.com,iamcredentials.googleapis.com,cloudresourcemanager.googleapis.com,serviceusage.googleapis.com'
        fi
```

The native host lifecycle supplies `SBX_AGENT` and `SBX_SANDBOX_NAME`. The guard skips client
Copilot. Host commands require native plan approval. Each sandbox gets a separate SBX secret
entry using the same host ADC; these are not separate Google keys.
Those two exact hosts cover the approved `eu` default and the Haiku `europe-west1` override.
Claude uses `aiplatform.eu.rep.googleapis.com` for `eu` and `aiplatform.us.rep.googleapis.com`
for `us`, not `eu-aiplatform.googleapis.com` or `us-aiplatform.googleapis.com`.
Use the exact hosts required by the approved regions, including `aiplatform.googleapis.com`
for the global endpoint and `<region>-aiplatform.googleapis.com` for specific regions.
Do not broaden the secret to `*.googleapis.com`.
The token source's executable, configuration, dependencies and any wrapper must remain outside
all writable sandbox mounts. Do not mount the host gcloud directory, helper directory or host
temporary directory. Use an absolute executable path; the daemon does not inherit arbitrary
exports from the terminal that registered the secret.

Adding a secret after sandbox creation did not update its existing `ANTHROPIC_AUTH_TOKEN`.
`claude-sbx` therefore selects the public placeholder from sandbox-scoped native metadata and
passes it with `sbx env exec --env`. It rejects missing or ambiguous secrets, global fallback,
static credentials, non-Vertex/wildcard targets, and unsupported placeholders. It never resolves
the token itself. The default region must be covered by the scoped secret.
The custom-secret default is `on-demand`; the explicit `45m` policy avoids calling gcloud for
every credential use and refreshes the source before a typical one-hour access token expires.
The duration is not a Google token-expiry check: gcloud manages token renewal, and revoked or
expired host ADC still requires host-side reauthentication.

On 2026-10-07 the isolated experiment verified:

- No workspace or runtime credential mount, no ADC in the agent or root standard location,
  and completed Haiku 4.5 responses through Claude Code without Google authentication in Claude.
- A dummy bearer without a matching secret returned Vertex `401 UNAUTHENTICATED`; native
  substitution returned `200` and the required arithmetic answer.
- A host-only instrumented resolver was reused for two immediate requests in one sandbox exec
  and invoked again after the configured `10s` cache duration. Separate native execs could also
  re-resolve the source; cache measurements therefore used a single exec.
- A request with the same placeholder to `cloudresourcemanager.googleapis.com` returned
  `401 UNAUTHENTICATED` without resolving the Vertex secret. That host was allowed only in the
  disposable sandbox for the negative test.
- An intentional resolver failure after cache expiry returned `401`, not a successful model
  response. Restoring the source restored successful requests.
- Stop/start preserved successful model authentication. The direct absolute gcloud command,
  without the instrumentation wrapper, also completed a Claude response with `--refresh 45m`.
- Delete/recreate completed another Claude response with the direct gcloud source and only
  the public placeholder in the sandbox environment. Removal deleted the scoped custom secret,
  which had to be registered again for the recreated sandbox.

The short-duration check proves source re-resolution, not Google issuing a different token
after its real one-hour expiry. Host scoping limits substitution, not the ADC principal's IAM
permissions or the Vertex API paths the agent can call. The agent can still perform permitted
Vertex operations through the proxy; this is not a substitute for least-privilege IAM.
Removing a mount does not revoke a refresh token an agent might already have read. If prior
credential exposure is suspected, revoke it and reauthenticate on the host using the approved flow.

Deployment on 2026-10-07 migrated both existing client Claude sandboxes using native `sbx umount`,
without recreation or history deletion. The actual `claude-sbx` launcher completed a default
Sonnet 5.5 response through `aiplatform.eu.rep.googleapis.com` and a Haiku 4.5 response through
`europe-west1-aiplatform.googleapis.com`. Both sandboxes had no runtime credential mounts or ADC
in the agent/root standard locations. OAuth/STS/IAM, Cloud Resource Manager and Service Usage
network checks were explicitly denied, including old allow rules retained by existing sandboxes.
They were stopped again after verification.

`tests/validate.sh` passed all 52 tests, native kit checks and seven environment plans.
The current full `tests/smoke.sh claude` run passed its new host-only authentication/placeholder
check but stopped at the unrelated infrastructure assertion `Unexpected ripgrep: /usr/bin/rg`
before model checks. It is not a passing full smoke result; its disposable sandbox and scoped
secret were removed.

## Migrating an existing client Claude sandbox

Remove the old ADC-mount lifecycle hook before starting new sandboxes. The new `postCreate`
hook does not run for existing sandboxes, so register their scoped secrets explicitly using
the same `sbx secret set-custom` command with `--sandbox <name>`. Then stop Claude and revoke
the old mount with native SBX:

```bash
sbx ls
sbx stop <client-claude-sandbox-name>
sbx umount <client-claude-sandbox-name> \
  "$HOME/.config/gcloud/application_default_credentials.json:/home/agent/.config/gcloud/application_default_credentials.json"
sbx policy deny network --sandbox <client-claude-sandbox-name> \
  'oauth2.googleapis.com,sts.googleapis.com,iamcredentials.googleapis.com,cloudresourcemanager.googleapis.com,serviceusage.googleapis.com'
```

`sbx umount` works while stopped and revokes the saved mount without deleting sandbox history.
Remove any remaining sandbox-local ADC file or empty mount target, never the host ADC, and verify
the absence of ADC and `GOOGLE_APPLICATION_CREDENTIALS`. Setting skip-auth alone does not remove
a mount. Native scoped denies override old kit allow rules in existing sandboxes; fresh sandboxes
also use the reduced Vertex mixin, which no longer allows credential or project-management endpoints.
OAuth token renewal still takes place on the host, outside those sandbox network restrictions.

Relaunch using `SBX_PROFILE=client claude-sbx`. The launcher applies skip-auth and the scoped
placeholder to each new session. A plain `sbx run` bypasses this adapter and can retain the old
container environment. Native removal of a sandbox deletes its scoped secret; the `postCreate`
hook registers a new one after recreation.

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
and the existing Copilot sandbox had no ADC file. This is historical verification of the old
mounted-ADC flow, not proof of the current host-only configuration.

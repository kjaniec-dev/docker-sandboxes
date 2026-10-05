# Client Claude Code via Vertex AI

The committed configuration owns only the portable pieces:

- `CLAUDE_CODE_USE_VERTEX=1`,
- `ANTHROPIC_VERTEX_PROJECT_ID`,
- `CLOUD_ML_REGION`,
- Vertex/Google runtime egress,
- the same shared `dev` mixin, skills, MCP gateway and instructions as personal sandboxes.

Authentication intentionally remains machine/company specific.

## Why ADC is not committed here

Claude Code on Vertex uses Google Application Default Credentials / workload identity. Copying
`~/.config/gcloud`, a service-account JSON key, or another long-lived client credential into this
repository would be the wrong generic default and would unnecessarily expose host credentials to the
agent.

Preserve the client's already-approved ADC/WIF mechanism during the V3 rewrite.

If SBX needs extra machine-local declarations, create:

```text
~/.config/docker-sandboxes/client.sbxenv.yaml
```

`bin/sbx-dev` automatically merges that file after the committed client and common environment
files. Put only the minimum client-specific declarations there and do not commit it.

Example skeleton — adapt it to the client's approved mechanism, do not copy blindly:

```yaml
schemaVersion: "1"

# env:
#   GOOGLE_APPLICATION_CREDENTIALS: /sandbox-visible/path/adc.json
#
# additionalWorkspaces:
#   - path: /host/path/approved-auth-material
#     readOnly: true
```

If the current client implementation already has a safe, working auth path, migrate that behavior
as-is first. Redesigning enterprise authentication is a separate change from the SBX V3 cleanup.

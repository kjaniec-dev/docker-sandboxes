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

Authentication remains the client's approved ADC/WIF mechanism. No implemented ADC/WIF path was
found in this repository or its reachable Git history. Runtime and authentication validation on the
client machine is deferred at the user's request; the native environment plan has been validated.

Keep any required client-machine declarations in
`${XDG_CONFIG_HOME:-$HOME/.config}/docker-sandboxes/client.sbxenv.yaml`.
The launcher merges this native environment overlay after the committed client and common files.
Use the approved sandbox-visible ADC/WIF path as-is; do not replace it with a new credential flow.

Once the client configuration is available, run:

```bash
SBX_PROFILE=client SBX_SMOKE_MODEL=1 ./tests/smoke.sh claude
```

This creates a disposable environment using the same overlay and requires successful tooling, MCP,
skills, Chromium, lifecycle and completed model requests. Its result must be recorded separately from
portable kit and environment-plan validation.

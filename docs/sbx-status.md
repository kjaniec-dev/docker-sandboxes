# SBX read-only status (experimental)

Run `python3 bin/sbx-status` or `python3 bin/sbx-status --json` on the host with SBX 0.54+ installed.

The command attempts to summarize the installed CLI version, sandbox inventory,
disk accounting, host MCP registrations and diagnostics. It does **not** start,
stop, delete or reconfigure sandboxes, and does not run a model request.

Status values `error` and `unsupported_output` mean a CLI subcommand or
structured-output option is not supported by the installed release; they are
**not** a PASS. The report deliberately excludes sandbox names, mount paths,
OAuth metadata, secret values and full diagnostic payloads.

**Context and usage limitation:** `sbx df` measures host disk usage, not
model token usage. The SBX CLI does not provide a verified, universal API for
remaining context-window tokens or provider quotas across Claude, Codex,
OpenCode, Junie and Vertex. Check those metrics in each agent/provider's
supported interface. Never infer a percentage from sandbox memory or disk.

Manual owner check on macOS:

```bash
sbx version --json
python3 bin/sbx-status
python3 bin/sbx-status --json
sbx df
sbx mcp ls
sbx diagnose --format json
```

Compare the report with the native commands and record unsupported flags
or malformed output. Do not upload full diagnostics without redaction.

**Manual macOS smoke: PENDING / NOT RUN.** This utility is not a substitute
for `./tests/validate.sh` and the seven-profile `tests/smoke.sh` matrix.

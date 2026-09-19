#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

if ! codex mcp get serena --json 2>/dev/null | jq -e '
  .enabled == true and
  .transport.type == "stdio" and
  .transport.command == "serena" and
  .transport.args == ["start-mcp-server", "--context=codex", "--project-from-cwd"]
' >/dev/null; then
  codex mcp add serena -- serena start-mcp-server --context=codex --project-from-cwd
fi

if ! codex mcp get context7 --json 2>/dev/null | jq -e '
  .enabled == true and
  .transport.type == "streamable_http" and
  .transport.url == "https://mcp.context7.com/mcp"
' >/dev/null; then
  codex mcp add context7 --url https://mcp.context7.com/mcp
fi

echo "Codex bootstrap setup complete."

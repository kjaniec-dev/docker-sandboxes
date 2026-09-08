#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source "$ROOT/harnesses/junie/scripts/bootstrap.sh"

config="$tmp/.junie/mcp/mcp.json"
ensure_junie_mcp_config "$config"
jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.serena.args == ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"] and
  .mcpServers.context7.url == "https://mcp.context7.com/mcp"
' "$config" >/dev/null

printf '%s\n' '{"mcpServers":{"user":{"command":"custom"}}}' >"$config"
ensure_junie_mcp_config "$config"
jq -e '.mcpServers.user.command == "custom" and .mcpServers.serena.command == "serena"' "$config" >/dev/null

printf '%s\n' '{"mcpServers":{"context7":{"url":"https://mcp.context7.com/mcp","headers":{"X-Test":"keep"}}}}' >"$config"
ensure_junie_mcp_config "$config"
jq -e '.mcpServers.context7.headers["X-Test"] == "keep"' "$config" >/dev/null

printf '%s\n' '{"mcpServers":{"serena":{"command":"other"}}}' >"$config"
if ensure_junie_mcp_config "$config"; then
  echo 'Junie bootstrap accepted a conflicting Serena MCP entry' >&2
  exit 1
fi

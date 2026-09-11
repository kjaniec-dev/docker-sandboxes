#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=../../../shared/verify-toolchain.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/verify-toolchain.sh"

verify_toolchain_commands 'Antigravity ' agy serena

skills_dir="$HOME/.gemini/config/skills"
[[ -f "$skills_dir/using-superpowers/SKILL.md" ]] || {
  echo "missing Antigravity skill: superpowers" >&2
  exit 1
}
[[ -f "$skills_dir/brainstorming/SKILL.md" ]] || {
  echo "missing Antigravity skill: brainstorming" >&2
  exit 1
}
[[ -f "$skills_dir/caveman/SKILL.md" ]] || {
  echo "missing Antigravity skill: caveman" >&2
  exit 1
}
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || {
  echo "missing Antigravity skill: playwright-cli" >&2
  exit 1
}

[[ "$(agy --version)" == "1.1.27" ]] || {
  echo "unexpected Antigravity CLI version: $(agy --version)" >&2
  exit 1
}

verify_toolchain 'Antigravity ' named

jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.serena.args == ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"] and
  .mcpServers.context7.serverUrl == "https://mcp.context7.com/mcp"
' "$HOME/.gemini/config/mcp_config.json" >/dev/null || {
  echo "unexpected Antigravity MCP configuration" >&2
  exit 1
}

echo "agy-sbx verification passed"

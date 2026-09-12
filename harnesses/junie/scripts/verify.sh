#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=../../../shared/verify-toolchain.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/verify-toolchain.sh"

verify_toolchain_commands 'Junie ' junie serena

skills_dir="$HOME/.junie/skills"
[[ -f "$skills_dir/using-superpowers/SKILL.md" ]] || {
  echo 'missing Junie skill: superpowers' >&2
  exit 1
}
[[ -f "$skills_dir/brainstorming/SKILL.md" ]] || {
  echo 'missing Junie skill: brainstorming' >&2
  exit 1
}
[[ -f "$skills_dir/caveman/SKILL.md" ]] || {
  echo 'missing Junie skill: caveman' >&2
  exit 1
}
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || {
  echo 'missing Junie skill: playwright-cli' >&2
  exit 1
}

verify_toolchain 'Junie ' raw

jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.serena.args == ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"] and
  .mcpServers.context7.url == "https://mcp.context7.com/mcp"
' "$HOME/.junie/mcp/mcp.json" >/dev/null || {
  echo 'unexpected Junie MCP configuration' >&2
  exit 1
}

jq -e '.brave == true' "$HOME/.junie/config.json" >/dev/null || {
  echo 'unexpected Junie permission configuration' >&2
  exit 1
}

echo 'junie-sbx verification passed'

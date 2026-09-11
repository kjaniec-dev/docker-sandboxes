#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=../../../shared/verify-toolchain.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/verify-toolchain.sh"

verify_toolchain_commands 'OpenCode ' opencode serena

skills_dir="$HOME/.config/opencode/skills"
[[ -f "$skills_dir/using-superpowers/SKILL.md" ]] || {
  echo "missing OpenCode skill: superpowers" >&2
  exit 1
}
[[ -f "$skills_dir/brainstorming/SKILL.md" ]] || {
  echo "missing OpenCode skill: brainstorming" >&2
  exit 1
}
[[ -f "$skills_dir/caveman/SKILL.md" ]] || {
  echo "missing OpenCode skill: caveman" >&2
  exit 1
}
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || {
  echo "missing OpenCode skill: playwright-cli" >&2
  exit 1
}
verify_toolchain 'OpenCode ' named

config="$(opencode debug config)" || {
  echo "failed to resolve OpenCode config" >&2
  exit 1
}
jq -e '
  .enabled_providers == ["opencode-go"] and
  .mcp.serena.type == "local" and
  .mcp.context7.type == "remote" and
  .mcp.context7.url == "https://mcp.context7.com/mcp"
' <<<"$config" >/dev/null || {
  echo "unexpected OpenCode MCP configuration" >&2
  exit 1
}

echo "opencode-sbx verification passed"

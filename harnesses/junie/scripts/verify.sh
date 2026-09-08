#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

required_commands=(junie git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle)
for cmd in "${required_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "missing Junie command: $cmd" >&2
    exit 1
  }
done

skills_dir="$HOME/.junie/skills"
[[ -f "$skills_dir/caveman/SKILL.md" ]] || {
  echo 'missing Junie skill: caveman' >&2
  exit 1
}
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || {
  echo 'missing Junie skill: playwright-cli' >&2
  exit 1
}
superpowers_linked=0
for skill_link in "$skills_dir"/*; do
  [[ -L "$skill_link" ]] || continue
  if [[ "$(readlink "$skill_link")" == "$HOME/.junie/superpowers/skills/"* ]]; then
    superpowers_linked=1
  fi
done
[[ "$superpowers_linked" == 1 ]] || {
  echo 'missing Junie skill: superpowers' >&2
  exit 1
}

java_version="$(java --version 2>&1)"
grep -Fq '25.' <<<"$java_version" || {
  echo "unexpected Junie Java version: $java_version" >&2
  exit 1
}
grep -Fq '25.' <<<"$(javac --version)" || {
  echo "unexpected Junie javac version: $(javac --version)" >&2
  exit 1
}
mvn --version >/dev/null
gradle --version >/dev/null
[[ "$(node --version)" == 'v24.19.0' ]] || {
  echo "unexpected Junie Node version: $(node --version)" >&2
  exit 1
}
grep -Fq 'go1.26.6' <<<"$(go version)" || {
  echo "unexpected Junie Go version: $(go version)" >&2
  exit 1
}
docker compose version >/dev/null

jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.serena.args == ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"] and
  .mcpServers.context7.url == "https://mcp.context7.com/mcp"
' "$HOME/.junie/mcp/mcp.json" >/dev/null || {
  echo 'unexpected Junie MCP configuration' >&2
  exit 1
}

echo 'junie-sbx verification passed'

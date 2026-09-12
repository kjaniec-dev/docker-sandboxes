#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source "$ROOT/harnesses/junie/scripts/bootstrap.sh"

settings="$tmp/.junie/config.json"
mkdir -p "$(dirname "$settings")"
printf '%s\n' '{"model":"sonnet","brave":false}' >"$settings"
ensure_junie_config "$settings"
jq -e '.model == "sonnet" and .brave == true' "$settings" >/dev/null

ensure_junie_config "$settings"
jq -e 'keys | sort == ["brave", "model"]' "$settings" >/dev/null

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

mkdir -p "$tmp/bin"
cat >"$tmp/bin/junie" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
MOCK
chmod +x "$tmp/bin/junie"
for command_name in curl git playwright-cli; do
  ln -s junie "$tmp/bin/$command_name"
done

shared_skills="$tmp/shared-skills"
for skill in using-superpowers brainstorming caveman playwright-cli; do
  mkdir -p "$shared_skills/$skill"
  printf '%s\n' "$skill" >"$shared_skills/$skill/SKILL.md"
done

bootstrap_home="$tmp/bootstrap-home"
mkdir -p "$bootstrap_home"
bootstrap_output="$tmp/bootstrap-output.log"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" SHARED_SKILLS_ROOT="$shared_skills" \
  bash "$ROOT/harnesses/junie/scripts/bootstrap.sh" >"$bootstrap_output"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" SHARED_SKILLS_ROOT="$shared_skills" \
  bash "$ROOT/harnesses/junie/scripts/bootstrap.sh" >>"$bootstrap_output"

grep -Fxq 'Junie bootstrap setup complete.' "$bootstrap_output"
skills_link="$bootstrap_home/.junie/skills"
[[ -L "$skills_link" ]]
[[ "$(readlink "$skills_link")" == "$shared_skills" ]]
for skill in using-superpowers brainstorming caveman playwright-cli; do
  [[ -f "$skills_link/$skill/SKILL.md" ]]
done
jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.context7.url == "https://mcp.context7.com/mcp"
' "$bootstrap_home/.junie/mcp/mcp.json" >/dev/null
jq -e '.brave == true' "$bootstrap_home/.junie/config.json" >/dev/null
[[ ! -e "$bootstrap_home/.cache/claude-sbx/junie-bootstrap-v1" ]]

echo 'test_junie_bootstrap.sh: PASS'

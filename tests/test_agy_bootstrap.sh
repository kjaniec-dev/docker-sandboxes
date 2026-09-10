#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source "$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh"

config_dir="$tmp/config"
mkdir -p "$config_dir"
config="$config_dir/mcp_config.json"
printf '%s\n' '{"mcpServers":{"custom":{"command":"example"}}}' >"$config"
ensure_agy_mcp_config "$config"
jq -e '.mcpServers.custom.command == "example"' "$config" >/dev/null
jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.serena.args == ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"] and
  .mcpServers.serena.disabled == false and
  .mcpServers.context7.serverUrl == "https://mcp.context7.com/mcp" and
  .mcpServers.context7.disabled == false
' "$config" >/dev/null

ensure_agy_mcp_config "$config"
jq -e '.mcpServers | keys | sort == ["context7", "custom", "serena"]' "$config" >/dev/null

conflict_dir="$tmp/conflict"
mkdir -p "$conflict_dir"
conflict="$conflict_dir/mcp_config.json"
printf '%s\n' '{"mcpServers":{"serena":{"command":"other-serena"}}}' >"$conflict"
conflict_before="$(cksum <"$conflict")"
conflict_output="$tmp/conflict-output.log"
if ensure_agy_mcp_config "$conflict" >"$conflict_output" 2>&1; then
  echo "conflicting Antigravity MCP entry unexpectedly accepted" >&2
  exit 1
fi
grep -Fq "conflicting managed MCP entry 'serena'" "$conflict_output"
[[ "$(cksum <"$conflict")" == "$conflict_before" ]]

printf '%s\n' '{"mcpServers":{"context7":{"serverUrl":"https://user.example/mcp"}}}' >"$conflict"
if ensure_agy_mcp_config "$conflict" >/dev/null 2>&1; then
  echo "conflicting Antigravity context7 entry unexpectedly accepted" >&2
  exit 1
fi

missing="$config_dir/missing/mcp_config.json"
ensure_agy_mcp_config "$missing"
jq -e '.mcpServers.serena.command == "serena" and .mcpServers.context7.serverUrl == "https://mcp.context7.com/mcp"' "$missing" >/dev/null

invalid="$config_dir/invalid.json"
printf '%s\n' '{invalid json' >"$invalid"
invalid_before="$(cksum <"$invalid")"
if ensure_agy_mcp_config "$invalid"; then
  echo "invalid Antigravity MCP config unexpectedly accepted" >&2
  exit 1
fi
[[ "$(cksum <"$invalid")" == "$invalid_before" ]]

mkdir -p "$tmp/bin"
cat >"$tmp/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
exit 1
MOCK
chmod +x "$tmp/bin/git"
cat >"$tmp/bin/playwright-cli" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
exit 1
MOCK
chmod +x "$tmp/bin/playwright-cli"

export MOCK_FORBIDDEN_LOG="$tmp/forbidden.log"
PATH="$tmp/bin:$PATH"

shared_skills="$tmp/shared-skills"
for skill in using-superpowers brainstorming caveman playwright-cli; do
  mkdir -p "$shared_skills/$skill"
  printf '%s\n' "$skill" >"$shared_skills/$skill/SKILL.md"
done

bootstrap_home="$tmp/bootstrap-home"
mkdir -p "$bootstrap_home"
bootstrap_output="$tmp/bootstrap-output.log"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" SHARED_SKILLS_ROOT="$shared_skills" \
  bash "$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh" >"$bootstrap_output"

grep -Fxq 'Antigravity bootstrap setup complete.' "$bootstrap_output"
skills_link="$bootstrap_home/.gemini/config/skills"
[[ -L "$skills_link" ]]
[[ "$(readlink "$skills_link")" == "$shared_skills" ]]
for skill in using-superpowers brainstorming caveman playwright-cli; do
  [[ -f "$skills_link/$skill/SKILL.md" ]]
done
jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.context7.serverUrl == "https://mcp.context7.com/mcp"
' "$bootstrap_home/.gemini/config/mcp_config.json" >/dev/null
[[ ! -e "$bootstrap_home/.cache/claude-sbx/antigravity-bootstrap-v1" ]]
[[ ! -s "$MOCK_FORBIDDEN_LOG" ]]

HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" SHARED_SKILLS_ROOT="$shared_skills" \
  bash "$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh" >>"$bootstrap_output"
[[ -L "$skills_link" ]]
[[ "$(readlink "$skills_link")" == "$shared_skills" ]]
[[ ! -s "$MOCK_FORBIDDEN_LOG" ]]

echo "test_agy_bootstrap.sh: PASS"

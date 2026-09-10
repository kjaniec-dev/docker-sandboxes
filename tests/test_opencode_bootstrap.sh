#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source "$ROOT/harnesses/opencode/scripts/bootstrap.sh"

config_dir="$tmp/config"
mkdir -p "$config_dir"
config="$config_dir/config.json"
printf '%s\n' '{"model":"existing","mcp":{"custom":{"type":"remote","url":"https://example.test/mcp"}}}' >"$config"
ensure_opencode_config "$config"
jq -e '.model == "existing" and .mcp.custom.url == "https://example.test/mcp"' "$config" >/dev/null
jq -e '.mcp.serena.type == "local" and .mcp.context7.url == "https://mcp.context7.com/mcp"' "$config" >/dev/null
jq -e '.enabled_providers == ["opencode-go"]' "$config" >/dev/null
jq -e '.mcp.serena.command == ["serena", "start-mcp-server", "--context=ide-assistant", "--project-from-cwd"] and .mcp.serena.enabled == true and .mcp.context7.enabled == true and .["$schema"] == "https://opencode.ai/config.json"' "$config" >/dev/null

jsonc="$config_dir/opencode.jsonc"
printf '%s\n' '// user JSONC' '{"custom": true,}' >"$jsonc"
jsonc_before="$(cksum <"$jsonc")"
ensure_opencode_config "$config"
[[ "$(cksum <"$jsonc")" == "$jsonc_before" ]]

jsonc_only_dir="$tmp/jsonc-only"
mkdir -p "$jsonc_only_dir"
jsonc_only="$jsonc_only_dir/opencode.jsonc"
printf '%s\n' '{"jsoncOnly":true}' >"$jsonc_only"
jsonc_only_before="$(cksum <"$jsonc_only")"
ensure_opencode_config "$jsonc_only_dir/config.json"
jq -e '.mcp.serena.enabled == true and .mcp.context7.enabled == true' "$jsonc_only_dir/config.json" >/dev/null
[[ "$(cksum <"$jsonc_only")" == "$jsonc_only_before" ]]

conflict_dir="$tmp/conflict"
mkdir -p "$conflict_dir"
conflict_jsonc="$conflict_dir/opencode.jsonc"
printf '%s\n' '// conflicting user MCP entry' '{"mcp":{"serena":{"type":"remote","url":"https://user.example/mcp"}},}' >"$conflict_jsonc"
conflict_jsonc_before="$(cksum <"$conflict_jsonc")"
conflict_config="$conflict_dir/config.json"
conflict_output="$tmp/conflict-output.log"
if ensure_opencode_config "$conflict_config" >"$conflict_output" 2>&1; then
  echo "conflicting JSONC MCP entry unexpectedly accepted" >&2
  exit 1
fi
grep -Fq "conflicting managed MCP entry" "$conflict_output"
[[ ! -e "$conflict_config" ]]
[[ "$(cksum <"$conflict_jsonc")" == "$conflict_jsonc_before" ]]

missing="$config_dir/missing/config.json"
ensure_opencode_config "$missing"
jq -e '.mcp.serena.enabled == true and .mcp.context7.enabled == true and .enabled_providers == ["opencode-go"]' "$missing" >/dev/null

invalid="$config_dir/invalid.json"
printf '%s\n' '{invalid json' >"$invalid"
invalid_before="$(cksum <"$invalid")"
if ensure_opencode_config "$invalid"; then
  echo "invalid OpenCode config unexpectedly accepted" >&2
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
mkdir -p "$bootstrap_home/.config/opencode"
bootstrap_kit_config="$bootstrap_home/.config/opencode/opencode.json"
printf '%s\n' '{"kitGenerated":true}' >"$bootstrap_kit_config"
bootstrap_kit_config_before="$(cksum <"$bootstrap_kit_config")"
bootstrap_jsonc="$bootstrap_home/.config/opencode/opencode.jsonc"
printf '%s\n' '{"jsoncOnly":true}' >"$bootstrap_jsonc"
bootstrap_jsonc_before="$(cksum <"$bootstrap_jsonc")"
bootstrap_output="$tmp/bootstrap-output.log"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" SHARED_SKILLS_ROOT="$shared_skills" \
  bash "$ROOT/harnesses/opencode/scripts/bootstrap.sh" >"$bootstrap_output"
[[ "$(cksum <"$bootstrap_kit_config")" == "$bootstrap_kit_config_before" ]]
printf '%s\n' '{"mcp":{"gateway":{"type":"remote","url":"https://gateway.example.test/mcp"}}}' >"$bootstrap_kit_config"
bootstrap_gateway_before="$(cksum <"$bootstrap_kit_config")"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" SHARED_SKILLS_ROOT="$shared_skills" \
  bash "$ROOT/harnesses/opencode/scripts/bootstrap.sh" >>"$bootstrap_output"

grep -Fxq 'OpenCode bootstrap setup complete.' "$bootstrap_output"
skills_link="$bootstrap_home/.config/opencode/skills"
[[ -L "$skills_link" ]]
[[ "$(readlink "$skills_link")" == "$shared_skills" ]]
for skill in using-superpowers brainstorming caveman playwright-cli; do
  [[ -f "$skills_link/$skill/SKILL.md" ]]
done
jq -e '
  .["$schema"] == "https://opencode.ai/config.json" and
  (.mcp | keys == ["context7", "serena"]) and
  .mcp.serena.type == "local" and
  .mcp.serena.enabled == true and
  .mcp.context7.type == "remote" and
  .mcp.context7.url == "https://mcp.context7.com/mcp" and
  .mcp.context7.enabled == true and
  .enabled_providers == ["opencode-go"]
' "$bootstrap_home/.config/opencode/config.json" >/dev/null
jq -e '. == {"mcp":{"gateway":{"type":"remote","url":"https://gateway.example.test/mcp"}}}' "$bootstrap_kit_config" >/dev/null
[[ "$(cksum <"$bootstrap_kit_config")" == "$bootstrap_gateway_before" ]]
[[ "$(cksum <"$bootstrap_jsonc")" == "$bootstrap_jsonc_before" ]]
[[ ! -e "$bootstrap_home/.cache/claude-sbx/opencode-bootstrap-v1" ]]
[[ ! -s "$MOCK_FORBIDDEN_LOG" ]]

echo "test_opencode_bootstrap.sh: PASS"

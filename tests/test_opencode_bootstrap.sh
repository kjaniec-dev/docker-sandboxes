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
printf '%s\n' "$*" >>"$MOCK_GIT_LOG"
if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" ]]; then
  printf '%s\n' "$MOCK_CAVEMAN_REVISION"
  exit 0
fi
if [[ "${1:-}" == "clone" ]]; then
  target="${@: -1}"
  mkdir -p "$target/.git" "$target/skills" "$target/skills/caveman" "$target/skills/superpowers"
  exit 0
fi
if [[ "${1:-}" == "-C" && "${3:-}" == "pull" ]]; then
  if [[ "$2" == */caveman ]]; then
    exit 1
  fi
  exit 0
fi
exit 1
MOCK
chmod +x "$tmp/bin/git"
cat >"$tmp/bin/playwright-cli" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_PLAYWRIGHT_LOG"
MOCK
chmod +x "$tmp/bin/playwright-cli"

export MOCK_GIT_LOG="$tmp/git.log"
export MOCK_CAVEMAN_REVISION="9aa63945a349bef17206540650db48c30fafbdf2"
export MOCK_PLAYWRIGHT_LOG="$tmp/playwright.log"
PATH="$tmp/bin:$PATH"

existing="$tmp/existing"
mkdir -p "$existing/.git"
ensure_git_checkout "$existing" https://example.test/repo.git
grep -Fq -- "-C $existing pull --ff-only" "$MOCK_GIT_LOG"

superpowers="$tmp/superpowers"
ensure_git_checkout "$superpowers" https://github.com/obra/superpowers.git
grep -Fq -- "clone --depth=1 https://github.com/obra/superpowers.git $superpowers" "$MOCK_GIT_LOG"

caveman="$tmp/caveman"
ensure_git_checkout "$caveman" https://github.com/JuliusBrussee/caveman.git v2.2.0
grep -Fq -- "clone --depth=1 --branch v2.2.0 https://github.com/JuliusBrussee/caveman.git $caveman" "$MOCK_GIT_LOG"
ensure_git_checkout "$caveman" https://github.com/JuliusBrussee/caveman.git v2.2.0
[[ "$(grep -Fc -- "clone --depth=1 --branch v2.2.0 https://github.com/JuliusBrussee/caveman.git $caveman" "$MOCK_GIT_LOG")" == 1 ]]
if grep -Fq -- "-C $caveman pull --ff-only" "$MOCK_GIT_LOG"; then
  echo "pinned Caveman checkout was pulled on second run" >&2
  exit 1
fi

non_git="$tmp/non-git"
mkdir -p "$non_git"
if ensure_git_checkout "$non_git" https://example.test/repo.git; then
  echo "non-git checkout path unexpectedly accepted" >&2
  exit 1
fi

bootstrap_home="$tmp/bootstrap-home"
mkdir -p "$bootstrap_home/.config/opencode"
bootstrap_kit_config="$bootstrap_home/.config/opencode/opencode.json"
printf '%s\n' '{"kitGenerated":true}' >"$bootstrap_kit_config"
bootstrap_kit_config_before="$(cksum <"$bootstrap_kit_config")"
bootstrap_jsonc="$bootstrap_home/.config/opencode/opencode.jsonc"
printf '%s\n' '{"jsoncOnly":true}' >"$bootstrap_jsonc"
bootstrap_jsonc_before="$(cksum <"$bootstrap_jsonc")"
bootstrap_output="$tmp/bootstrap-output.log"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" bash "$ROOT/harnesses/opencode/scripts/bootstrap.sh" >"$bootstrap_output"
[[ "$(cksum <"$bootstrap_kit_config")" == "$bootstrap_kit_config_before" ]]
printf '%s\n' '{"mcp":{"gateway":{"type":"remote","url":"https://gateway.example.test/mcp"}}}' >"$bootstrap_kit_config"
bootstrap_gateway_before="$(cksum <"$bootstrap_kit_config")"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" bash "$ROOT/harnesses/opencode/scripts/bootstrap.sh" >>"$bootstrap_output"

grep -Fxq 'OpenCode bootstrap setup complete.' "$bootstrap_output"
[[ -d "$bootstrap_home/.opencode/superpowers/.git" ]]
[[ -d "$bootstrap_home/.opencode/caveman/.git" ]]
[[ -L "$bootstrap_home/.agents/skills/superpowers" ]]
[[ -L "$bootstrap_home/.agents/skills/caveman" ]]
[[ "$(readlink "$bootstrap_home/.agents/skills/superpowers")" == "$bootstrap_home/.opencode/superpowers/skills" ]]
[[ "$(readlink "$bootstrap_home/.agents/skills/caveman")" == "$bootstrap_home/.opencode/caveman/skills/caveman" ]]
grep -Fq -- 'install --skills agents --global' "$MOCK_PLAYWRIGHT_LOG"
[[ "$(wc -l <"$MOCK_PLAYWRIGHT_LOG" | tr -d ' ')" == 2 ]]
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
[[ -f "$bootstrap_home/.cache/claude-sbx/opencode-bootstrap-v1" ]]
[[ "$(grep -Fc -- "clone --depth=1 https://github.com/obra/superpowers.git $bootstrap_home/.opencode/superpowers" "$MOCK_GIT_LOG")" == 1 ]]
[[ "$(grep -Fc -- "clone --depth=1 --branch v2.2.0 https://github.com/JuliusBrussee/caveman.git $bootstrap_home/.opencode/caveman" "$MOCK_GIT_LOG")" == 1 ]]
if grep -Fq -- "-C $bootstrap_home/.opencode/caveman pull --ff-only" "$MOCK_GIT_LOG"; then
  echo "main bootstrap pulled pinned Caveman checkout" >&2
  exit 1
fi

echo "test_opencode_bootstrap.sh: PASS"

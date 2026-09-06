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
printf '%s\n' "$*" >>"$MOCK_GIT_LOG"
if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" ]]; then
  printf '%s\n' "$MOCK_CAVEMAN_REVISION"
  exit 0
fi
if [[ "${1:-}" == "clone" ]]; then
  target="${@: -1}"
  mkdir -p "$target/.git" "$target/skills/brainstorming" "$target/skills/debugging" "$target/skills/caveman"
  touch "$target/skills/brainstorming/SKILL.md" "$target/skills/debugging/SKILL.md" "$target/skills/caveman/SKILL.md"
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
if [[ "${1:-}" == "install" ]]; then
  mkdir -p "$HOME/.agents/skills/playwright-cli"
  touch "$HOME/.agents/skills/playwright-cli/SKILL.md"
fi
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

non_git="$tmp/non-git"
mkdir -p "$non_git"
if ensure_git_checkout "$non_git" https://example.test/repo.git; then
  echo "non-git checkout path unexpectedly accepted" >&2
  exit 1
fi

bootstrap_home="$tmp/bootstrap-home"
mkdir -p "$bootstrap_home"
bootstrap_output="$tmp/bootstrap-output.log"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" bash "$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh" >"$bootstrap_output"

grep -Fxq 'Antigravity bootstrap setup complete.' "$bootstrap_output"
[[ -d "$bootstrap_home/.gemini/superpowers/.git" ]]
[[ -d "$bootstrap_home/.gemini/caveman/.git" ]]
[[ -L "$bootstrap_home/.gemini/config/skills/brainstorming" ]]
[[ "$(readlink "$bootstrap_home/.gemini/config/skills/brainstorming")" == "$bootstrap_home/.gemini/superpowers/skills/brainstorming" ]]
[[ -L "$bootstrap_home/.gemini/config/skills/debugging" ]]
[[ -L "$bootstrap_home/.gemini/config/skills/caveman" ]]
[[ "$(readlink "$bootstrap_home/.gemini/config/skills/caveman")" == "$bootstrap_home/.gemini/caveman/skills/caveman" ]]
grep -Fq -- 'install --skills agents --global' "$MOCK_PLAYWRIGHT_LOG"
[[ -L "$bootstrap_home/.gemini/config/skills/playwright-cli" ]]
[[ "$(readlink "$bootstrap_home/.gemini/config/skills/playwright-cli")" == "$bootstrap_home/.agents/skills/playwright-cli" ]]
jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.context7.serverUrl == "https://mcp.context7.com/mcp"
' "$bootstrap_home/.gemini/config/mcp_config.json" >/dev/null
[[ -f "$bootstrap_home/.cache/claude-sbx/antigravity-bootstrap-v1" ]]

HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" bash "$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh" >>"$bootstrap_output"
[[ "$(grep -Fc -- "clone --depth=1 https://github.com/obra/superpowers.git $bootstrap_home/.gemini/superpowers" "$MOCK_GIT_LOG")" == 1 ]]
[[ "$(grep -Fc -- "clone --depth=1 --branch v2.2.0 https://github.com/JuliusBrussee/caveman.git $bootstrap_home/.gemini/caveman" "$MOCK_GIT_LOG")" == 1 ]]
if grep -Fq -- "-C $bootstrap_home/.gemini/caveman pull --ff-only" "$MOCK_GIT_LOG"; then
  echo "Antigravity bootstrap pulled pinned Caveman checkout" >&2
  exit 1
fi

echo "test_agy_bootstrap.sh: PASS"

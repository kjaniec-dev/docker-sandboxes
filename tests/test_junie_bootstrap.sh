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

snapshot_discovery_entries() {
  local directory="$1"
  snapshot_discovery_tree "$directory" | LC_ALL=C sort
}

snapshot_discovery_tree() {
  local directory="$1"
  local prefix="${2:-}" entry name type
  local -a entries
  shopt -s nullglob dotglob
  entries=("$directory"/*)
  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    if [[ -L "$entry" ]]; then
      type=symlink
    elif [[ -d "$entry" ]]; then
      type=directory
    elif [[ -f "$entry" ]]; then
      type=file
    else
      type=other
    fi
    printf '%s\t%s\n' "$prefix$name" "$type"
    if [[ "$type" == directory ]]; then
      snapshot_discovery_tree "$entry" "$prefix$name/"
    fi
  done
}

assert_discovery_snapshot() {
  local expected="$1" directory="$2" actual
  actual="$(snapshot_discovery_entries "$directory")"
  [[ "$actual" == "$expected" ]] || {
    echo "bootstrap changed the skills discovery directory: $actual" >&2
    exit 1
  }
  [[ "$actual" != *$'\tsymlink'* ]] || {
    echo 'bootstrap created a skills symlink' >&2
    exit 1
  }
}

bootstrap_home="$tmp/bootstrap-home"
mkdir -p "$bootstrap_home"
skills_dir="$bootstrap_home/.junie/skills"
mkdir -p "$skills_dir"
printf '%s\n' user-owned >"$skills_dir/user-skill.md"
skills_before_snapshot="$(snapshot_discovery_entries "$skills_dir")"
skills_before="$(cksum <"$skills_dir/user-skill.md")"
bootstrap_output="$tmp/bootstrap-output.log"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" \
  bash "$ROOT/harnesses/junie/scripts/bootstrap.sh" >"$bootstrap_output"
assert_discovery_snapshot "$skills_before_snapshot" "$skills_dir"
HOME="$bootstrap_home" PATH="$tmp/bin:$PATH" \
  bash "$ROOT/harnesses/junie/scripts/bootstrap.sh" >>"$bootstrap_output"
assert_discovery_snapshot "$skills_before_snapshot" "$skills_dir"

grep -Fxq 'Junie bootstrap setup complete.' "$bootstrap_output"
[[ -d "$skills_dir" && ! -L "$skills_dir" ]]
[[ "$(cksum <"$skills_dir/user-skill.md")" == "$skills_before" ]]
jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.context7.url == "https://mcp.context7.com/mcp"
' "$bootstrap_home/.junie/mcp/mcp.json" >/dev/null
jq -e '.brave == true' "$bootstrap_home/.junie/config.json" >/dev/null
[[ ! -e "$bootstrap_home/.cache/claude-sbx/junie-bootstrap-v1" ]]

echo 'test_junie_bootstrap.sh: PASS'

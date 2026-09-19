#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/harnesses/claude-code/scripts/bootstrap.sh"
plugin_list=$'superpowers@claude-plugins-official\ncontext7@claude-plugins-official'
plugin_is_installed "superpowers@claude-plugins-official" "$plugin_list"
! plugin_is_installed "frontend-design@claude-plugins-official" "$plugin_list"
if grep -Eq 'install\.sh|bin/install\.js|npx .*JuliusBrussee/caveman' "$ROOT/harnesses/claude-code/scripts/bootstrap.sh"; then
  echo "bootstrap must use the Caveman plugin path only" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/plugin-state"
cat >"$tmp/bin/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_CLAUDE_LOG"
if [[ "$*" == 'plugin list' ]]; then
  for plugin_file in "$MOCK_PLUGIN_STATE"/*; do
    [[ -f "$plugin_file" ]] || continue
    basename "$plugin_file"
  done
elif [[ "${1:-}" == plugin && "${2:-}" == install ]]; then
  touch "$MOCK_PLUGIN_STATE/${3:-}"
fi
MOCK
chmod +x "$tmp/bin/claude"
cat >"$tmp/bin/playwright-cli" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
exit 1
MOCK
chmod +x "$tmp/bin/playwright-cli"

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

skills_dir="$tmp/home/.claude/skills"
mkdir -p "$skills_dir"
printf '%s\n' user-owned >"$skills_dir/user-skill.md"
skills_before_snapshot="$(snapshot_discovery_entries "$skills_dir")"
skills_before="$(cksum <"$skills_dir/user-skill.md")"

for run in 1 2; do
  MOCK_CLAUDE_LOG="$tmp/claude.log" MOCK_PLUGIN_STATE="$tmp/plugin-state" \
    MOCK_FORBIDDEN_LOG="$tmp/forbidden.log" \
    HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
    bash "$ROOT/harnesses/claude-code/scripts/bootstrap.sh" \
    >"$tmp/bootstrap-$run.log"
  assert_discovery_snapshot "$skills_before_snapshot" "$skills_dir"
done

[[ -d "$skills_dir" && ! -L "$skills_dir" ]]
[[ "$(cksum <"$skills_dir/user-skill.md")" == "$skills_before" ]]
for plugin in superpowers@claude-plugins-official frontend-design@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official caveman@caveman; do
  [[ "$(grep -Fc "plugin install $plugin" "$tmp/claude.log")" == 1 ]]
done
[[ "$(grep -Fc 'plugin marketplace add JuliusBrussee/caveman' "$tmp/claude.log")" == 1 ]]
[[ ! -e "$tmp/home/.cache/claude-sbx/bootstrap-v1" ]]
[[ ! -s "$tmp/forbidden.log" ]]

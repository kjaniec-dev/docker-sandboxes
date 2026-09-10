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

shared_skills="$tmp/shared-skills"
for skill in using-superpowers brainstorming caveman playwright-cli; do
  mkdir -p "$shared_skills/$skill"
  printf '%s\n' "$skill" >"$shared_skills/$skill/SKILL.md"
done

for run in 1 2; do
  MOCK_CLAUDE_LOG="$tmp/claude.log" MOCK_PLUGIN_STATE="$tmp/plugin-state" \
    MOCK_FORBIDDEN_LOG="$tmp/forbidden.log" SHARED_SKILLS_ROOT="$shared_skills" \
    HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
    bash "$ROOT/harnesses/claude-code/scripts/bootstrap.sh" \
    >"$tmp/bootstrap-$run.log"
done

skills_link="$tmp/home/.claude/skills"
[[ -L "$skills_link" ]]
[[ "$(readlink "$skills_link")" == "$shared_skills" ]]
for skill in using-superpowers brainstorming caveman playwright-cli; do
  [[ -f "$skills_link/$skill/SKILL.md" ]]
done
for plugin in superpowers@claude-plugins-official frontend-design@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official caveman@caveman; do
  [[ "$(grep -Fc "plugin install $plugin" "$tmp/claude.log")" == 1 ]]
done
[[ "$(grep -Fc 'plugin marketplace add JuliusBrussee/caveman' "$tmp/claude.log")" == 1 ]]
[[ ! -e "$tmp/home/.cache/claude-sbx/bootstrap-v1" ]]
[[ ! -s "$tmp/forbidden.log" ]]

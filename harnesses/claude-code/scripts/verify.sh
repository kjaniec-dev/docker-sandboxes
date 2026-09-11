#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=../../../shared/verify-toolchain.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/verify-toolchain.sh"

verify_toolchain_commands '' claude

skills_dir="$HOME/.claude/skills"
[[ -f "$skills_dir/using-superpowers/SKILL.md" ]] || {
  echo "missing Claude skill: superpowers" >&2
  exit 1
}
[[ -f "$skills_dir/brainstorming/SKILL.md" ]] || {
  echo "missing Claude skill: brainstorming" >&2
  exit 1
}
[[ -f "$skills_dir/caveman/SKILL.md" ]] || {
  echo "missing Claude skill: caveman" >&2
  exit 1
}
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || {
  echo "missing Claude skill: playwright-cli" >&2
  exit 1
}
verify_toolchain '' raw
plugins="$(claude plugin list)"
for plugin in superpowers@claude-plugins-official frontend-design@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official caveman@caveman; do
  grep -Fq "$plugin" <<<"$plugins" || {
    echo "missing Claude plugin: $plugin" >&2
    exit 1
  }
done
echo "claude-sbx verification passed"

#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=../../../shared/verify-toolchain.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/verify-toolchain.sh"

verify_toolchain_commands '' codex serena

skills_dir="$HOME/.agents/skills"
[[ -f "$skills_dir/using-superpowers/SKILL.md" ]] || {
  echo "missing Codex skill: superpowers" >&2
  exit 1
}
[[ -f "$skills_dir/brainstorming/SKILL.md" ]] || {
  echo "missing Codex skill: brainstorming" >&2
  exit 1
}
[[ -f "$skills_dir/caveman/SKILL.md" ]] || {
  echo "missing Codex skill: caveman" >&2
  exit 1
}
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || {
  echo "missing Codex skill: playwright-cli" >&2
  exit 1
}
verify_toolchain '' raw
echo "codex-sbx verification passed"

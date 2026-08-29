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

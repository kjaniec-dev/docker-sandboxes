#!/usr/bin/env bash
set -euo pipefail

plugin_is_installed() {
  local plugin="$1"
  local list_text="$2"
  grep -Fq "$plugin" <<<"$list_text"
}

refresh_official_marketplace() {
  if ! claude plugin marketplace update claude-plugins-official; then
    claude plugin marketplace add anthropics/claude-plugins-official
    claude plugin marketplace update claude-plugins-official
  fi
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

refresh_official_marketplace
plugin_list="$(claude plugin list 2>/dev/null || true)"

install_plugin() {
  local plugin="$1"
  if plugin_is_installed "$plugin" "$plugin_list"; then
    echo "already installed: $plugin"
    return 0
  fi
  claude plugin install "$plugin"
  plugin_list+=$'\n'"$plugin"
}

install_plugin "superpowers@claude-plugins-official"
install_plugin "frontend-design@claude-plugins-official"
install_plugin "context7@claude-plugins-official"
install_plugin "serena@claude-plugins-official"

if ! plugin_is_installed "caveman@caveman" "$plugin_list"; then
  claude plugin marketplace add JuliusBrussee/caveman
  claude plugin install caveman@caveman
  plugin_list+=$'\n'"caveman@caveman"
else
  echo "already installed: caveman@caveman"
fi

playwright-cli install --skills
mkdir -p "$HOME/.cache/claude-sbx"
touch "$HOME/.cache/claude-sbx/bootstrap-v1"

echo "Claude plugin/bootstrap setup complete."

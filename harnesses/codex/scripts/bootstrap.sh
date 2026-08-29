#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

if ! codex mcp get serena --json 2>/dev/null | jq -e '
  .enabled == true and
  .transport.type == "stdio" and
  .transport.command == "serena" and
  .transport.args == ["start-mcp-server", "--context=codex", "--project-from-cwd"]
' >/dev/null; then
  codex mcp add serena -- serena start-mcp-server --context=codex --project-from-cwd
fi

if ! codex mcp get context7 --json 2>/dev/null | jq -e '
  .enabled == true and
  .transport.type == "streamable_http" and
  .transport.url == "https://mcp.context7.com/mcp"
' >/dev/null; then
  codex mcp add context7 --url https://mcp.context7.com/mcp
fi

superpowers_dir="$HOME/.codex/superpowers"
if [[ -d "$superpowers_dir/.git" ]]; then
  git -C "$superpowers_dir" pull --ff-only
elif [[ ! -e "$superpowers_dir" ]]; then
  git clone --depth=1 https://github.com/obra/superpowers.git "$superpowers_dir"
else
  echo "Codex bootstrap: refusing to replace non-git $superpowers_dir" >&2
  exit 1
fi
mkdir -p "$HOME/.agents/skills"
ln -sfn "$superpowers_dir/skills" "$HOME/.agents/skills/superpowers"
playwright-cli install --skills agents --global

mkdir -p "$HOME/.cache/claude-sbx"
touch "$HOME/.cache/claude-sbx/codex-bootstrap-v1"

echo "Codex bootstrap setup complete."

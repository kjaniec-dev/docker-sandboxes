#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/claude-sbx"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
touch "$tmp/.gitignore"
if ensure_worktrees_ignored "$tmp"; then
  echo "guard should fail when .worktrees/ is not ignored" >&2
  exit 1
fi
printf '.worktrees/\n' >> "$tmp/.gitignore"
mkdir -p "$tmp/.worktrees"
ensure_worktrees_ignored "$tmp"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for target in test verify rebuild rebuild-claude rebuild-codex; do
  grep -Eq "^${target}:" "$ROOT/Makefile" || {
    echo "missing Make target: $target" >&2
    exit 1
  }
done

grep -Fq './bin/claude-sbx-rebuild' "$ROOT/README.md"
grep -Fq './bin/codex-sbx-rebuild' "$ROOT/README.md"
grep -Fq 'claude-sbx' "$ROOT/docs/usage.md"
grep -Fq 'codex-sbx' "$ROOT/docs/usage.md"
grep -Fq 'sbx secret set openai --oauth' "$ROOT/docs/usage.md"
grep -Fq 'claude-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq 'codex-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq '.worktrees/' "$ROOT/docs/usage.md"

for path in \
  '.claude/skills/playwright-cli/SKILL.md' \
  '.playwright/cli.config.json' \
  '.serena/project.yml'; do
  if git -C "$ROOT" check-ignore -q "$path"; then
    echo "project configuration must not be ignored: $path" >&2
    exit 1
  fi
done

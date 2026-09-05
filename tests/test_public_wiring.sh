#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for target in test verify rebuild rebuild-claude rebuild-codex rebuild-opencode verify-opencode; do
  grep -Eq "^${target}:" "$ROOT/Makefile" || {
    echo "missing Make target: $target" >&2
    exit 1
  }
done

grep -Fq './bin/claude-sbx-rebuild' "$ROOT/README.md"
grep -Fq './bin/codex-sbx-rebuild' "$ROOT/README.md"
grep -Fq '# Claude, Codex, and OpenCode Docker Sandboxes' "$ROOT/README.md"
grep -Fq './bin/opencode-sbx-rebuild' "$ROOT/README.md"
grep -Fq 'ln -sfn "$PWD/bin/opencode-sbx"' "$ROOT/README.md"
grep -Fq 'opencode-sbx' "$ROOT/README.md"
grep -Fq 'claude-sbx' "$ROOT/docs/usage.md"
grep -Fq 'codex-sbx' "$ROOT/docs/usage.md"
grep -Fq 'opencode-sbx' "$ROOT/docs/usage.md"
grep -Fq 'ln -sfn "$PWD/bin/opencode-sbx-rebuild"' "$ROOT/docs/usage.md"
grep -Fq 'sbx secret set openai --oauth' "$ROOT/docs/usage.md"
grep -Fq 'opencode-sbx:local' "$ROOT/docs/usage.md"
grep -Fq 'opencode-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq 'make rebuild-opencode' "$ROOT/docs/usage.md"
grep -Fq 'sbx secret set-custom' "$ROOT/docs/usage.md"
grep -Fq 'OPENCODE_API_KEY' "$ROOT/docs/usage.md"
grep -Fq 'opencode-go' "$ROOT/docs/usage.md"
grep -Fq 'enabled_providers' "$ROOT/docs/usage.md"
grep -Fq 'Host-level OpenCode config is not inherited' "$ROOT/docs/usage.md"
grep -Fq 'sbx rm <sandbox-name>' "$ROOT/docs/usage.md"
grep -Fq 'source /path/to/claude-sbx/bin/opencode-sbx' "$ROOT/docs/usage.md"
grep -Fq 'harnesses/opencode/scripts/verify.sh' "$ROOT/docs/usage.md"
for provider in openai anthropic google xai groq openrouter; do
  grep -Fq "sbx secret set $provider" "$ROOT/docs/usage.md"
done
if grep -Fq 'sbx secret set aws' "$ROOT/docs/usage.md"; then
  echo 'unsupported AWS provider quick-start must not be documented' >&2
  exit 1
fi
if grep -Fq 'aws' "$ROOT/docs/superpowers/specs/2026-09-05-opencode-sbx-design.md"; then
  echo 'unsupported AWS provider must not be documented in OpenCode spec' >&2
  exit 1
fi

for path in "$ROOT/harnesses/opencode/scripts/bootstrap.sh"; do
  [[ -x "$path" ]] || {
    echo "missing executable OpenCode script: $path" >&2
    exit 1
  }
done
grep -Fq 'claude-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq 'codex-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq '.worktrees/' "$ROOT/docs/usage.md"

if grep -Eiq '(/Users/|/Volumes/|/home/|sk-[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,})' \
  "$ROOT/README.md" "$ROOT/docs/usage.md"; then
  echo 'public documentation contains private path or credential-like value' >&2
  exit 1
fi

for path in \
  '.claude/skills/playwright-cli/SKILL.md' \
  '.playwright/cli.config.json' \
  '.serena/project.yml'; do
  if git -C "$ROOT" check-ignore -q "$path"; then
    echo "project configuration must not be ignored: $path" >&2
    exit 1
  fi
done

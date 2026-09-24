#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for target in test verify rebuild rebuild-claude rebuild-codex rebuild-opencode rebuild-agy rebuild-junie verify-opencode verify-agy verify-junie; do
  grep -Eq "^${target}:" "$ROOT/Makefile" || {
    echo "missing Make target: $target" >&2
    exit 1
  }
done

rebuild_body="$(sed -n '/^rebuild:/,/^[^[:space:]]/p' "$ROOT/Makefile")"
grep -Fq '$(MAKE) rebuild-claude rebuild-codex rebuild-opencode rebuild-agy rebuild-junie' <<<"$rebuild_body"

grep -Fq './bin/claude-sbx-rebuild' "$ROOT/README.md"
grep -Fq './bin/codex-sbx-rebuild' "$ROOT/README.md"
grep -Fq '# Claude, Codex, OpenCode, Antigravity, and Junie Docker Sandboxes' "$ROOT/README.md"
grep -Fq 'Docker Sandboxes 0.43.0' "$ROOT/README.md"
grep -Fq 'Docker Sandboxes (`sbx`), minimum version 0.43.0' "$ROOT/docs/usage.md"
grep -Fq 'native read-only `skills` mode' "$ROOT/README.md"
grep -Fq 'sbx create --name' "$ROOT/docs/usage.md"
grep -Fq -- '--skills=readonly' "$ROOT/docs/usage.md"
grep -Fq 'sbx inspect <sandbox-name>' "$ROOT/docs/usage.md"
grep -Fq 'Signed git kits' "$ROOT/docs/usage.md"
grep -Fq 'credential' "$ROOT/docs/usage.md"
grep -Fq 'Claude local kit' "$ROOT/docs/usage.md"
grep -Fq 'harnesses/claude-code/kit/' "$ROOT/docs/usage.md"
grep -Fq "No \`~/.sbxenv.yaml\` file is needed." "$ROOT/docs/usage.md"
grep -Fq "Claude passes its local v2 kit directly to \`sbx create\`." "$ROOT/docs/usage.md"
grep -Fq 'not a local v2 kit path' "$ROOT/docs/usage.md"
grep -Fq 'sandboxOptions.skills' "$ROOT/docs/usage.md"
grep -Fq 'agent: claude' "$ROOT/docs/usage.md"
grep -Fq 'forward agent arguments after the' "$ROOT/docs/usage.md"
grep -Fq 'sbx secret set mcp:<server>:client_secret' "$ROOT/docs/usage.md"
grep -Fq 'mcp:<server>.client_secret' "$ROOT/docs/usage.md"
grep -Fq './bin/agy-sbx-rebuild' "$ROOT/README.md"
grep -Fq 'ln -sfn "$PWD/bin/agy-sbx"' "$ROOT/README.md"
grep -Fq 'agy-sbx' "$ROOT/README.md"
grep -Fq './bin/junie-sbx-rebuild' "$ROOT/README.md"
grep -Fq 'junie-sbx' "$ROOT/README.md"
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
grep -Fq 'agy-sbx' "$ROOT/docs/usage.md"
grep -Fq 'ln -sfn "$PWD/bin/agy-sbx-rebuild"' "$ROOT/docs/usage.md"
grep -Fq 'agy-sbx:local' "$ROOT/docs/usage.md"
grep -Fq 'agy-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq 'make rebuild-agy' "$ROOT/docs/usage.md"
grep -Fq 'GEMINI_API_KEY' "$ROOT/docs/usage.md"
grep -Fq 'source /path/to/claude-sbx/bin/agy-sbx' "$ROOT/docs/usage.md"
grep -Fq 'harnesses/antigravity-cli/scripts/verify.sh' "$ROOT/docs/usage.md"
grep -Fq 'junie-sbx' "$ROOT/docs/usage.md"
grep -Fq 'junie-sbx:local' "$ROOT/docs/usage.md"
grep -Fq 'junie-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq 'make rebuild-junie' "$ROOT/docs/usage.md"
grep -Fq 'harnesses/junie/scripts/verify.sh' "$ROOT/docs/usage.md"
if grep -Fq 'links the shared skill store' "$ROOT/docs/usage.md" ||
  grep -Fq '~/.junie/skills/' "$ROOT/docs/usage.md"; then
  echo 'public documentation contains obsolete Junie manual skills-link guidance' >&2
  exit 1
fi
for path in "$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh"; do
  [[ -x "$path" ]] || {
    echo "missing executable Antigravity script: $path" >&2
    exit 1
  }
done
for path in "$ROOT/harnesses/junie/scripts/bootstrap.sh"; do
  [[ -x "$path" ]] || {
    echo "missing executable Junie script: $path" >&2
    exit 1
  }
done
grep -Fq 'claude-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq 'codex-<repo-slug>-<8-hex-path-digest>' "$ROOT/docs/usage.md"
grep -Fq '.worktrees/' "$ROOT/docs/usage.md"

if grep -Eiq '(/Users/|/Volumes/|/home/|sk-[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,})' \
  "$ROOT/README.md" "$ROOT/docs/usage.md" "$ROOT/AGENTS.md"; then
  echo 'public documentation contains private path or credential-like value' >&2
  exit 1
fi

for public_file in "$ROOT/README.md" "$ROOT/docs/usage.md" "$ROOT/AGENTS.md" \
  "$ROOT/bin/sbx-policy-audit"; do
  if grep -Fq '0.42.1' "$public_file"; then
    echo "stale Docker Sandboxes 0.42.1 reference: $public_file" >&2
    exit 1
  fi
  if grep -Eq 'skills_root|SHARED_SKILLS_ROOT|link_shared_skills' "$public_file"; then
    echo "obsolete manual skills lifecycle reference: $public_file" >&2
    exit 1
  fi
done

for path in \
  '.claude/skills/playwright-cli/SKILL.md' \
  '.playwright/cli.config.json' \
  '.serena/project.yml'; do
  if git -C "$ROOT" check-ignore -q "$path"; then
    echo "project configuration must not be ignored: $path" >&2
    exit 1
  fi
done

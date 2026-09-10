#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$ROOT/harnesses/junie/kit/spec.yaml"

grep -Fq 'name: junie-sbx' "$KIT"
grep -Fq 'kind: sandbox' "$KIT"
grep -Fq 'image: junie-sbx:local' "$KIT"
for domain in github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com \
  codeload.github.com registry.npmjs.org nodejs.org go.dev proxy.golang.org sum.golang.org \
  pypi.org files.pythonhosted.org astral.sh mcp.context7.com cdn.playwright.dev \
  playwright.download.prss.microsoft.com junie.jetbrains.com registry.jetbrains.team \
  api.jetbrains.com account.jetbrains.com api.openai.com auth.openai.com api.anthropic.com \
  generativelanguage.googleapis.com api.x.ai openrouter.ai api.openrouter.ai; do
  grep -Fq -- "- $domain" "$KIT" || {
    echo "missing Junie kit domain: $domain" >&2
    exit 1
  }
done
grep -Fq '.worktrees/' "$KIT"
grep -Fq 'playwright-cli' "$KIT"
grep -Fq 'OpenJDK 25' "$KIT"

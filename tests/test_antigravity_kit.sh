#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$ROOT/harnesses/antigravity-cli/kit/spec.yaml"

grep -Fq 'name: antigravity-sbx' "$KIT"
grep -Fq 'agent: antigravity' "$KIT"
for domain in github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com \
  codeload.github.com registry.npmjs.org nodejs.org go.dev proxy.golang.org sum.golang.org \
  pypi.org files.pythonhosted.org astral.sh mcp.context7.com cdn.playwright.dev \
  playwright.download.prss.microsoft.com storage.googleapis.com accounts.google.com \
  oauth2.googleapis.com sts.googleapis.com aicode.googleapis.com cloudcode-pa.googleapis.com \
  generativelanguage.googleapis.com antigravity.google.com; do
  grep -Fq -- "- $domain" "$KIT" || {
    echo "missing Antigravity kit domain: $domain" >&2
    exit 1
  }
done
grep -Fq '.worktrees/' "$KIT"
grep -Fq 'playwright-cli' "$KIT"
grep -Fq 'OpenJDK 25' "$KIT"

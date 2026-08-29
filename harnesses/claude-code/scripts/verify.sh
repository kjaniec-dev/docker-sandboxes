#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

required_commands=(claude git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle)
for cmd in "${required_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing command: $cmd" >&2; exit 1; }
done
grep -Fq '25.' <<<"$(java --version 2>&1 | head -n1)" || { echo "unexpected Java version: $(java --version 2>&1 | head -n1)" >&2; exit 1; }
grep -Fq '25.' <<<"$(javac --version)" || { echo "unexpected javac version: $(javac --version)" >&2; exit 1; }
mvn --version >/dev/null
gradle --version >/dev/null
[[ "$(node --version)" == "v24.19.0" ]] || { echo "unexpected Node version: $(node --version)" >&2; exit 1; }
grep -Fq 'go1.26.6' <<<"$(go version)" || { echo "unexpected Go version: $(go version)" >&2; exit 1; }
docker compose version >/dev/null
plugins="$(claude plugin list)"
for plugin in superpowers@claude-plugins-official frontend-design@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official caveman@caveman; do
  grep -Fq "$plugin" <<<"$plugins" || { echo "missing Claude plugin: $plugin" >&2; exit 1; }
done
echo "claude-sbx verification passed"

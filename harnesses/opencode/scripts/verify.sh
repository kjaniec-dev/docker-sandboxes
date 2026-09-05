#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

check_java_major() {
  local label="$1"
  local version="$2"
  local line
  local major="unknown"
  while IFS= read -r line; do
    if [[ "$label" == 'Java' && "$line" =~ ^openjdk[[:space:]]([0-9]+)\. ]]; then
      major="${BASH_REMATCH[1]}"
      break
    fi
    if [[ "$label" == 'javac' && "$line" =~ ^javac[[:space:]]([0-9]+)\. ]]; then
      major="${BASH_REMATCH[1]}"
      break
    fi
  done <<<"$version"
  # Require Java 25.
  [[ "$major" == "25" ]] || {
    echo "unexpected OpenCode $label version: $version (expected major 25; observed major $major)" >&2
    exit 1
  }
}

required_commands=(opencode git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle)
for cmd in "${required_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing OpenCode command: $cmd" >&2; exit 1; }
done
[[ -f "$HOME/.agents/skills/superpowers/README.md" || -d "$HOME/.agents/skills/superpowers" ]] || { echo "missing OpenCode skill: superpowers" >&2; exit 1; }
[[ -f "$HOME/.agents/skills/caveman/SKILL.md" ]] || { echo "missing OpenCode skill: caveman" >&2; exit 1; }
[[ -f "$HOME/.agents/skills/playwright-cli/SKILL.md" ]] || { echo "missing OpenCode skill: playwright-cli" >&2; exit 1; }
java_version="$(java --version 2>&1)"
check_java_major 'Java' "$java_version"
javac_version="$(javac --version 2>&1)"
check_java_major 'javac' "$javac_version"
if ! mvn --version >/dev/null 2>&1; then
  echo 'OpenCode Maven verification failed: mvn --version' >&2
  exit 1
fi
if ! gradle --version >/dev/null 2>&1; then
  echo 'OpenCode Gradle verification failed: gradle --version' >&2
  exit 1
fi
[[ "$(node --version)" == "v24.19.0" ]] || { echo "unexpected OpenCode Node version: $(node --version)" >&2; exit 1; }
grep -Fq 'go1.26.6' <<<"$(go version)" || { echo "unexpected OpenCode Go version: $(go version)" >&2; exit 1; }
if ! docker compose version >/dev/null 2>&1; then
  echo 'OpenCode Docker Compose verification failed: docker compose version' >&2
  exit 1
fi

config="$(opencode debug config)" || { echo "failed to resolve OpenCode config" >&2; exit 1; }
jq -e '
  .mcp.serena.type == "local" and
  .mcp.context7.type == "remote" and
  .mcp.context7.url == "https://mcp.context7.com/mcp"
' <<<"$config" >/dev/null || { echo "unexpected OpenCode MCP configuration" >&2; exit 1; }

echo "opencode-sbx verification passed"

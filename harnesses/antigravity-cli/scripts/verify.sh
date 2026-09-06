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
    echo "unexpected Antigravity $label version: $version (expected major 25; observed major $major)" >&2
    exit 1
  }
}

required_commands=(agy git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle)
for cmd in "${required_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing Antigravity command: $cmd" >&2; exit 1; }
done

skills_dir="$HOME/.gemini/config/skills"
[[ -f "$skills_dir/caveman/SKILL.md" ]] || { echo "missing Antigravity skill: caveman" >&2; exit 1; }
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || { echo "missing Antigravity skill: playwright-cli" >&2; exit 1; }
superpowers_linked=0
for skill_link in "$skills_dir"/*; do
  [[ -L "$skill_link" ]] || continue
  if [[ "$(readlink "$skill_link")" == "$HOME/.gemini/superpowers/skills/"* ]]; then
    superpowers_linked=1
  fi
done
[[ "$superpowers_linked" == 1 ]] || { echo "missing Antigravity skill: superpowers" >&2; exit 1; }

[[ "$(agy --version)" == "1.1.27" ]] || { echo "unexpected Antigravity CLI version: $(agy --version)" >&2; exit 1; }

java_version="$(java --version 2>&1)"
check_java_major 'Java' "$java_version"
javac_version="$(javac --version 2>&1)"
check_java_major 'javac' "$javac_version"
if ! mvn --version >/dev/null 2>&1; then
  echo 'Antigravity Maven verification failed: mvn --version' >&2
  exit 1
fi
if ! gradle --version >/dev/null 2>&1; then
  echo 'Antigravity Gradle verification failed: gradle --version' >&2
  exit 1
fi
[[ "$(node --version)" == "v24.19.0" ]] || { echo "unexpected Antigravity Node version: $(node --version)" >&2; exit 1; }
grep -Fq 'go1.26.6' <<<"$(go version)" || { echo "unexpected Antigravity Go version: $(go version)" >&2; exit 1; }
if ! docker compose version >/dev/null 2>&1; then
  echo 'Antigravity Docker Compose verification failed: docker compose version' >&2
  exit 1
fi

jq -e '
  .mcpServers.serena.command == "serena" and
  .mcpServers.serena.args == ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"] and
  .mcpServers.context7.serverUrl == "https://mcp.context7.com/mcp"
' "$HOME/.gemini/config/mcp_config.json" >/dev/null || { echo "unexpected Antigravity MCP configuration" >&2; exit 1; }

echo "agy-sbx verification passed"

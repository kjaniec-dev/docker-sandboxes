#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
for directory in .claude/skills .agents/skills .config/opencode/skills .gemini/config/skills .junie/skills; do
  for skill in using-superpowers brainstorming caveman playwright-cli; do
    mkdir -p "$tmp/home/$directory/$skill"
    touch "$tmp/home/$directory/$skill/SKILL.md"
  done
done
mkdir -p "$tmp/home/.junie/mcp"
config='{"mcpServers":{"serena":{"command":"serena","args":["start-mcp-server","--context=ide-assistant","--project-from-cwd"]},"context7":{"url":"https://mcp.context7.com/mcp","serverUrl":"https://mcp.context7.com/mcp"}}}'
printf '%s\n' "$config" >"$tmp/home/.junie/mcp/mcp.json"
printf '%s\n' "$config" >"$tmp/home/.gemini/config/mcp_config.json"
cat >"$tmp/mock-command" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "${0##*/}" in
  java|javac)
    printf '%s\n' "${MOCK_PROXY_DIAGNOSTIC:-Picked up JAVA_TOOL_OPTIONS: -Dhttp.proxyHost=proxy}" >&2
    if [[ "${0##*/}" == java ]]; then
      printf 'openjdk %s 2026-07-21\nOpenJDK Runtime Environment\n' "${MOCK_JAVA_VERSION:-25.0.4}"
    else
      printf 'javac %s\n' "${MOCK_JAVAC_VERSION:-25.0.4}"
    fi
    [[ "${MOCK_FAIL_COMMAND:-}" != "${0##*/}" ]]
    ;;
  node) printf '%s\n' 'v24.19.0' ;;
  go) printf '%s\n' 'go version go1.26.6 linux/arm64' ;;
  agy) printf '%s\n' '1.1.27' ;;
  claude) printf '%s\n' superpowers@claude-plugins-official frontend-design@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official caveman@caveman ;;
  opencode) printf '%s\n' '{"enabled_providers":["opencode-go"],"mcp":{"serena":{"type":"local"},"context7":{"type":"remote","url":"https://mcp.context7.com/mcp"}}}' ;;
esac
MOCK
chmod +x "$tmp/mock-command"
for cmd in claude codex opencode agy junie git gh curl wget ssh rg fd yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle; do
  ln -s "$tmp/mock-command" "$tmp/bin/$cmd"
done

for harness in claude-code codex opencode antigravity-cli junie; do
  verify="$ROOT/harnesses/$harness/scripts/verify.sh"
  # Proxy diagnostics precede the version; they must not determine the major.
  for version in 25.0.4 25; do
    HOME="$tmp/home" PATH="$tmp/bin:$PATH" MOCK_JAVA_VERSION="$version" MOCK_JAVAC_VERSION="$version" \
      bash "$verify" >"$tmp/output" 2>&1 || {
      cat "$tmp/output" >&2
      echo "$harness rejected Java $version with proxy diagnostics" >&2
      exit 1
    }
  done
  for override in MOCK_JAVA_VERSION=21.0.4 MOCK_JAVAC_VERSION=21.0.4 MOCK_FAIL_COMMAND=java MOCK_FAIL_COMMAND=javac; do
    if env HOME="$tmp/home" PATH="$tmp/bin:$PATH" MOCK_PROXY_DIAGNOSTIC='Picked up JAVA_TOOL_OPTIONS: -Dtest=25.0' "$override" bash "$verify" >"$tmp/output" 2>&1; then
      echo "$harness accepted invalid Java verification: $override" >&2
      exit 1
    fi
  done
done
echo 'test_java_verification.sh: PASS'

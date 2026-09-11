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
if [[ "${MOCK_FAIL_COMMAND:-}" == "${0##*/}" && ( "${0##*/}" == node || "${0##*/}" == go ) ]]; then
  echo "${0##*/}: tool diagnostic" >&2
  exit 37
fi
case "${0##*/}" in
  java|javac)
    printf '%s\n' "${MOCK_PROXY_DIAGNOSTIC:-Picked up JAVA_TOOL_OPTIONS: -Dhttp.proxyHost=proxy}" >&2
    if [[ "${0##*/}" == java ]]; then
      printf 'openjdk %s 2026-07-21\nOpenJDK Runtime Environment\n' "${MOCK_JAVA_VERSION:-25.0.4}"
    else
      printf 'javac %s\n' "${MOCK_JAVAC_VERSION:-25.0.4}"
    fi
    ;;
  node) printf '%s\n' "${MOCK_NODE_VERSION:-v24.19.0}" ;;
  go) printf '%s\n' "${MOCK_GO_VERSION:-go version go1.26.6 linux/arm64}" ;;
  agy) printf '%s\n' '1.1.27' ;;
  claude) printf '%s\n' superpowers@claude-plugins-official frontend-design@claude-plugins-official context7@claude-plugins-official serena@claude-plugins-official caveman@caveman ;;
  opencode) printf '%s\n' '{"enabled_providers":["opencode-go"],"mcp":{"serena":{"type":"local"},"context7":{"type":"remote","url":"https://mcp.context7.com/mcp"}}}' ;;
esac
if [[ "${MOCK_FAIL_COMMAND:-}" == "${0##*/}" ]]; then
  echo "${0##*/}: tool diagnostic" >&2
  exit 37
fi
MOCK
chmod +x "$tmp/mock-command"
for cmd in claude codex opencode agy junie git gh curl wget ssh rg fd yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle; do
  ln -s "$tmp/mock-command" "$tmp/bin/$cmd"
done

# Isolate PATH so a host installation cannot mask a missing sandbox command.
for cmd in bash dirname grep jq; do
  ln -s "$(command -v "$cmd")" "$tmp/bin/$cmd"
done
# shellcheck disable=SC2016 # Expansion belongs to the child shell.
PATH=/nonexistent "$tmp/bin/bash" -c 'before="$-"; source "$1" || exit; [[ "$-" == "$before" ]] || exit 1; echo sourced' _ "$ROOT/shared/verify-toolchain.sh" >"$tmp/output" 2>&1
[[ "$(<"$tmp/output")" == sourced ]]

for harness in claude-code codex opencode antigravity-cli junie; do
  verify="$ROOT/harnesses/$harness/scripts/verify.sh"
  case "$harness" in
  claude-code)
    agent=claude
    prefix=''
    ;;
  codex)
    agent=codex
    prefix=''
    ;;
  opencode)
    agent=opencode
    prefix='OpenCode '
    ;;
  antigravity-cli)
    agent=agy
    prefix='Antigravity '
    ;;
  junie)
    agent=junie
    prefix='Junie '
    ;;
  esac
  # Sourcing must work without any external commands or installed toolchain.
  # shellcheck disable=SC2016 # Expansion belongs to the child shell.
  PATH=/nonexistent "$tmp/bin/bash" -c 'source "$1" || exit; echo sourced' _ "$verify" >"$tmp/output" 2>&1
  [[ "$(<"$tmp/output")" == sourced ]]

  for cmd in "$agent" git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle; do
    mv "$tmp/bin/$cmd" "$tmp/absent-command"
    status=0
    HOME="$tmp/home" PATH="$tmp/bin" "$tmp/bin/bash" "$verify" >"$tmp/output" 2>"$tmp/error" || status=$?
    mv "$tmp/absent-command" "$tmp/bin/$cmd"
    [[ "$status" == 1 && ! -s "$tmp/output" ]]
    grep -Fxq "missing ${prefix}command: $cmd" "$tmp/error"
  done
  if [[ "$harness" != claude-code ]]; then
    mv "$tmp/bin/serena" "$tmp/absent-command"
    status=0
    HOME="$tmp/home" PATH="$tmp/bin" "$tmp/bin/bash" "$verify" >"$tmp/output" 2>"$tmp/error" || status=$?
    mv "$tmp/absent-command" "$tmp/bin/serena"
    [[ "$status" == 1 ]]
    grep -Fxq "missing ${prefix}command: serena" "$tmp/error"
  fi
  for override in MOCK_NODE_VERSION=v22.0.0 MOCK_GO_VERSION='go version go1.25.0 linux/arm64'; do
    status=0
    env HOME="$tmp/home" PATH="$tmp/bin" "$override" "$tmp/bin/bash" "$verify" >"$tmp/output" 2>"$tmp/error" || status=$?
    [[ "$status" == 1 && ! -s "$tmp/output" ]]
    case "$override" in
    MOCK_NODE*) grep -Fxq "unexpected ${prefix}Node version: v22.0.0" "$tmp/error" ;;
    MOCK_GO*) grep -Fxq "unexpected ${prefix}Go version: go version go1.25.0 linux/arm64" "$tmp/error" ;;
    esac
  done
  for cmd in mvn gradle docker; do
    status=0
    HOME="$tmp/home" PATH="$tmp/bin" MOCK_FAIL_COMMAND="$cmd" "$tmp/bin/bash" "$verify" >"$tmp/output" 2>"$tmp/error" || status=$?
    [[ ! -s "$tmp/output" ]]
    if [[ "$harness" == opencode || "$harness" == antigravity-cli ]]; then
      [[ "$status" == 1 ]]
      case "$cmd" in
      mvn) message='Maven verification failed: mvn --version' ;;
      gradle) message='Gradle verification failed: gradle --version' ;;
      docker) message='Docker Compose verification failed: docker compose version' ;;
      esac
      grep -Fxq "${prefix}$message" "$tmp/error"
    else
      [[ "$status" == 37 ]]
      grep -Fxq "$cmd: tool diagnostic" "$tmp/error"
    fi
  done
  for cmd in node go; do
    status=0
    HOME="$tmp/home" PATH="$tmp/bin" MOCK_FAIL_COMMAND="$cmd" "$tmp/bin/bash" "$verify" >"$tmp/output" 2>"$tmp/error" || status=$?
    [[ "$status" == 1 && ! -s "$tmp/output" ]]
    grep -Fxq "$cmd: tool diagnostic" "$tmp/error"
  done
  # Proxy diagnostics precede the version; they must not determine the major.
  for version in 25.0.4 25; do
    HOME="$tmp/home" PATH="$tmp/bin:$PATH" MOCK_JAVA_VERSION="$version" MOCK_JAVAC_VERSION="$version" \
      bash "$verify" >"$tmp/output" 2>&1 || {
      cat "$tmp/output" >&2
      echo "$harness rejected Java $version with proxy diagnostics" >&2
      exit 1
    }
  done
  for override in MOCK_JAVA_VERSION=21.0.4 MOCK_JAVAC_VERSION=21.0.4 MOCK_JAVA_VERSION=unknown MOCK_JAVAC_VERSION=unknown MOCK_FAIL_COMMAND=java MOCK_FAIL_COMMAND=javac; do
    if env HOME="$tmp/home" PATH="$tmp/bin:$PATH" MOCK_PROXY_DIAGNOSTIC='Picked up JAVA_TOOL_OPTIONS: -Dtest=25.0' "$override" bash "$verify" >"$tmp/output" 2>&1; then
      echo "$harness accepted invalid Java verification: $override" >&2
      exit 1
    fi
  done
done
echo 'test_java_verification.sh: PASS'

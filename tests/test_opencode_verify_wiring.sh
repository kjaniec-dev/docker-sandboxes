#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$ROOT/harnesses/opencode/scripts/verify.sh"

for cmd in opencode git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle; do
  grep -Fq "$cmd" "$VERIFY"
done
grep -Fq 'java --version' "$VERIFY"
grep -Fq 'javac --version' "$VERIFY"
grep -Fq '25.' "$VERIFY"
grep -Fq 'v24.19.0' "$VERIFY"
grep -Fq 'go1.26.6' "$VERIFY"
grep -Fq 'mvn --version' "$VERIFY"
grep -Fq 'gradle --version' "$VERIFY"
grep -Fq 'docker compose version' "$VERIFY"
grep -Fq 'opencode debug config' "$VERIFY"
grep -Fq 'enabled_providers' "$VERIFY"
grep -Fq 'opencode-go' "$VERIFY"
grep -Fq 'serena' "$VERIFY"
grep -Fq 'superpowers' "$VERIFY"
grep -Fq 'caveman' "$VERIFY"
grep -Fq 'playwright-cli' "$VERIFY"
grep -Fq 'opencode-sbx verification passed' "$VERIFY"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.agents/skills/superpowers" \
  "$tmp/home/.agents/skills/caveman" "$tmp/home/.agents/skills/playwright-cli"
touch "$tmp/home/.agents/skills/superpowers/README.md" \
  "$tmp/home/.agents/skills/caveman/SKILL.md" \
  "$tmp/home/.agents/skills/playwright-cli/SKILL.md"

cat >"$tmp/mock-command" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

command_name="$(basename "$0")"
if [[ "${MOCK_FAIL_COMMAND:-}" == "$command_name" ]]; then
  exit 1
fi

case "$command_name" in
  java)
    printf '%s\n' "${MOCK_JAVA_OUTPUT:-openjdk 25.0.1 2025-09-16}"
    ;;
  javac)
    printf '%s\n' "${MOCK_JAVAC_OUTPUT:-javac 25.0.1}"
    ;;
  node)
    printf '%s\n' 'v24.19.0'
    ;;
  go)
    printf '%s\n' 'go version go1.26.6 darwin/arm64'
    ;;
  opencode)
    [[ "${1:-}" == 'debug' && "${2:-}" == 'config' ]]
    printf '%s\n' "$MOCK_CONFIG"
    ;;
  *)
    ;;
esac
MOCK
chmod +x "$tmp/mock-command"
for cmd in opencode git gh curl wget ssh rg fd yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle; do
  ln -s "$tmp/mock-command" "$tmp/bin/$cmd"
done
ln -s "$(command -v jq)" "$tmp/bin/jq"

mock_config='{"enabled_providers":["opencode-go"],"mcp":{"serena":{"type":"local"},"context7":{"type":"remote","url":"https://mcp.context7.com/mcp"}}}'
mock_java_output='openjdk 25.0.1 2025-09-16'
mock_javac_output='javac 25.0.1'
mock_fail_command=''

run_verify() {
  local output="$1"
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
    MOCK_CONFIG="$mock_config" MOCK_JAVA_OUTPUT="$mock_java_output" \
    MOCK_JAVAC_OUTPUT="$mock_javac_output" MOCK_FAIL_COMMAND="$mock_fail_command" \
    bash "$VERIFY" >"$output" 2>"$output.err"
}

run_verify "$tmp/success"
grep -Fxq 'opencode-sbx verification passed' "$tmp/success"

mock_java_output=$'Picked up JAVA_TOOL_OPTIONS: -Dhttp.proxyPort=3128\nopenjdk 25.0.4 2025-09-16'
run_verify "$tmp/java-tool-options"
grep -Fxq 'opencode-sbx verification passed' "$tmp/java-tool-options"

mock_java_output='openjdk 125.0.1 2025-09-16'
if run_verify "$tmp/java-failure"; then
  echo 'Java major-version failure was not detected' >&2
  exit 1
fi
grep -Fq 'observed major 125' "$tmp/java-failure.err"

mock_java_output='openjdk 25.0.1 2025-09-16'
mock_javac_output='javac 125.0.1'
if run_verify "$tmp/javac-failure"; then
  echo 'javac major-version failure was not detected' >&2
  exit 1
fi
grep -Fq 'unexpected OpenCode javac version' "$tmp/javac-failure.err"
grep -Fq 'observed major 125' "$tmp/javac-failure.err"

mock_javac_output='javac 25.0.1'
mock_config='{"enabled_providers":["opencode-go"],"mcp":{"serena":{"type":"local"}}}'
if run_verify "$tmp/mcp-failure"; then
  echo 'invalid MCP configuration was not detected' >&2
  exit 1
fi
grep -Fq 'unexpected OpenCode MCP configuration' "$tmp/mcp-failure.err"

mock_config='{"enabled_providers":["opencode-go"],"mcp":{"serena":{"type":"local"},"context7":{"type":"remote","url":"https://mcp.context7.com/mcp"}}}'
rm "$tmp/home/.agents/skills/playwright-cli/SKILL.md"
if run_verify "$tmp/skill-failure"; then
  echo 'missing Playwright skill was not detected' >&2
  exit 1
fi
grep -Fq 'missing OpenCode skill: playwright-cli' "$tmp/skill-failure.err"
touch "$tmp/home/.agents/skills/playwright-cli/SKILL.md"

for failing_command in mvn gradle docker; do
  mock_fail_command="$failing_command"
  if run_verify "$tmp/$failing_command-failure"; then
    echo "$failing_command failure was not detected" >&2
    exit 1
  fi
  case "$failing_command" in
    mvn) expected_error='OpenCode Maven verification failed: mvn --version' ;;
    gradle) expected_error='OpenCode Gradle verification failed: gradle --version' ;;
    docker) expected_error='OpenCode Docker Compose verification failed: docker compose version' ;;
  esac
  grep -Fq "$expected_error" "$tmp/$failing_command-failure.err"
  mock_fail_command=''
done

echo "test_opencode_verify_wiring.sh: PASS"

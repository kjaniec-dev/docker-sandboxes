#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$ROOT/harnesses/antigravity-cli/scripts/verify.sh"

for cmd in agy git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle; do
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
grep -Fq 'agy --version' "$VERIFY"
grep -Fq '1.1.27' "$VERIFY"
grep -Fq 'mcp_config.json' "$VERIFY"
grep -Fq 'serena' "$VERIFY"
grep -Fq 'superpowers' "$VERIFY"
grep -Fq 'caveman' "$VERIFY"
grep -Fq 'playwright-cli' "$VERIFY"
grep -Fq 'agy-sbx verification passed' "$VERIFY"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" \
  "$tmp/home/.gemini/config/skills/caveman" \
  "$tmp/home/.gemini/config/skills/playwright-cli" \
  "$tmp/home/.gemini/superpowers/skills/brainstorming"
touch "$tmp/home/.gemini/config/skills/caveman/SKILL.md" \
  "$tmp/home/.gemini/config/skills/playwright-cli/SKILL.md" \
  "$tmp/home/.gemini/superpowers/skills/brainstorming/SKILL.md"
ln -s "$tmp/home/.gemini/superpowers/skills/brainstorming" \
  "$tmp/home/.gemini/config/skills/brainstorming"
printf '%s\n' '{"mcpServers":{"serena":{"command":"serena","args":["start-mcp-server","--context=ide-assistant","--project-from-cwd"],"disabled":false},"context7":{"serverUrl":"https://mcp.context7.com/mcp","disabled":false}}}' \
  >"$tmp/home/.gemini/config/mcp_config.json"

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
    printf '%s\n' 'go version go1.26.6 linux/arm64'
    ;;
  agy)
    printf '%s\n' "${MOCK_AGY_VERSION:-1.1.27}"
    ;;
  *)
    ;;
esac
MOCK
chmod +x "$tmp/mock-command"
for cmd in agy git gh curl wget ssh rg fd yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle; do
  ln -s "$tmp/mock-command" "$tmp/bin/$cmd"
done
ln -s "$(command -v jq)" "$tmp/bin/jq"

mock_java_output='openjdk 25.0.1 2025-09-16'
mock_javac_output='javac 25.0.1'
mock_agy_version='1.1.27'
mock_fail_command=''

run_verify() {
  local output="$1"
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
    MOCK_JAVA_OUTPUT="$mock_java_output" MOCK_JAVAC_OUTPUT="$mock_javac_output" \
    MOCK_AGY_VERSION="$mock_agy_version" MOCK_FAIL_COMMAND="$mock_fail_command" \
    bash "$VERIFY" >"$output" 2>"$output.err"
}

run_verify "$tmp/success"
grep -Fxq 'agy-sbx verification passed' "$tmp/success"

mock_agy_version='1.1.26'
if run_verify "$tmp/agy-failure"; then
  echo 'unexpected Antigravity CLI version was not detected' >&2
  exit 1
fi
grep -Fq 'unexpected Antigravity CLI version' "$tmp/agy-failure.err"
mock_agy_version='1.1.27'

mcp_config="$tmp/home/.gemini/config/mcp_config.json"
printf '%s\n' '{"mcpServers":{"serena":{"command":"serena"}}}' >"$mcp_config"
if run_verify "$tmp/mcp-failure"; then
  echo 'invalid Antigravity MCP configuration was not detected' >&2
  exit 1
fi
grep -Fq 'unexpected Antigravity MCP configuration' "$tmp/mcp-failure.err"
printf '%s\n' '{"mcpServers":{"serena":{"command":"serena","args":["start-mcp-server","--context=ide-assistant","--project-from-cwd"],"disabled":false},"context7":{"serverUrl":"https://mcp.context7.com/mcp","disabled":false}}}' >"$mcp_config"

rm "$tmp/home/.gemini/config/skills/playwright-cli/SKILL.md"
if run_verify "$tmp/skill-failure"; then
  echo 'missing Playwright skill was not detected' >&2
  exit 1
fi
grep -Fq 'missing Antigravity skill: playwright-cli' "$tmp/skill-failure.err"
touch "$tmp/home/.gemini/config/skills/playwright-cli/SKILL.md"

rm "$tmp/home/.gemini/config/skills/brainstorming"
if run_verify "$tmp/superpowers-failure"; then
  echo 'missing Superpowers skill link was not detected' >&2
  exit 1
fi
grep -Fq 'missing Antigravity skill: superpowers' "$tmp/superpowers-failure.err"
ln -s "$tmp/home/.gemini/superpowers/skills/brainstorming" \
  "$tmp/home/.gemini/config/skills/brainstorming"

for failing_command in mvn gradle docker; do
  mock_fail_command="$failing_command"
  if run_verify "$tmp/$failing_command-failure"; then
    echo "$failing_command failure was not detected" >&2
    exit 1
  fi
  case "$failing_command" in
    mvn) expected_error='Antigravity Maven verification failed: mvn --version' ;;
    gradle) expected_error='Antigravity Gradle verification failed: gradle --version' ;;
    docker) expected_error='Antigravity Docker Compose verification failed: docker compose version' ;;
  esac
  grep -Fq "$expected_error" "$tmp/$failing_command-failure.err"
  mock_fail_command=''
done

echo "test_agy_verify_wiring.sh: PASS"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'uv tool install serena-agent' "$ROOT/shared/install-user-toolchain.sh"
grep -Fq 'https://github.com/obra/superpowers.git' \
  "$ROOT/harnesses/codex/scripts/bootstrap.sh"
grep -Fq 'serena' "$ROOT/harnesses/codex/scripts/verify.sh"
grep -Fq 'superpowers' "$ROOT/harnesses/codex/scripts/verify.sh"
grep -Fq 'playwright-cli/SKILL.md' "$ROOT/harnesses/codex/scripts/verify.sh"
grep -Fq 'playwright-cli' "$ROOT/harnesses/codex/kit/spec.yaml"
grep -Fq 'playwright-cli install --skills agents --global' \
  "$ROOT/harnesses/codex/scripts/bootstrap.sh"
grep -Fq 'serena start-mcp-server --context=codex --project-from-cwd' \
  "$ROOT/harnesses/codex/scripts/bootstrap.sh"
grep -Fq 'codex mcp add context7 --url https://mcp.context7.com/mcp' \
  "$ROOT/harnesses/codex/scripts/bootstrap.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.codex"
cat >"$tmp/bin/codex" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "mcp" && "${2:-}" == "get" ]]; then
  printf '%s\n' '{"name":"serena","enabled":false,"transport":{"type":"stdio","command":"wrong-command","args":[]}}'
  exit 0
fi
if [[ "${1:-}" == "mcp" && "${2:-}" == "add" ]]; then
  printf '%s\n' "$*" >>"$MOCK_CODEX_LOG"
  exit 0
fi
exit 1
MOCK
chmod +x "$tmp/bin/codex"
cat >"$tmp/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "clone" ]]; then
  target="${@: -1}"
  mkdir -p "$target/.git" "$target/skills"
fi
MOCK
chmod +x "$tmp/bin/git"
cat >"$tmp/bin/playwright-cli" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"$MOCK_PLAYWRIGHT_LOG"
MOCK
chmod +x "$tmp/bin/playwright-cli"

MOCK_CODEX_LOG="$tmp/codex.log" MOCK_PLAYWRIGHT_LOG="$tmp/playwright.log" \
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
  bash "$ROOT/harnesses/codex/scripts/bootstrap.sh"
grep -Fq 'mcp add serena -- serena start-mcp-server --context=codex --project-from-cwd' \
  "$tmp/codex.log"
grep -Fq 'mcp add context7 --url https://mcp.context7.com/mcp' "$tmp/codex.log"
grep -Fq 'install --skills agents --global' "$tmp/playwright.log"
[[ -L "$tmp/home/.agents/skills/superpowers" ]]

echo "test_codex_integrations.sh: PASS"

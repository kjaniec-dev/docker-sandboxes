#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'uv tool install serena-agent' "$ROOT/shared/install-user-toolchain.sh"
grep -Fq 'serena' "$ROOT/harnesses/codex/scripts/verify.sh"
grep -Fq 'using-superpowers/SKILL.md' "$ROOT/harnesses/codex/scripts/verify.sh"
grep -Fq 'caveman/SKILL.md' "$ROOT/harnesses/codex/scripts/verify.sh"
grep -Fq 'playwright-cli/SKILL.md' "$ROOT/harnesses/codex/scripts/verify.sh"
grep -Fq 'playwright-cli' "$ROOT/harnesses/codex/kit/spec.yaml"
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
  name="${3:-}"
  if [[ -e "$MOCK_STATE/$name" ]]; then
    case "$name" in
      serena)
        printf '%s\n' '{"name":"serena","enabled":true,"transport":{"type":"stdio","command":"serena","args":["start-mcp-server","--context=codex","--project-from-cwd"]}}'
        ;;
      context7)
        printf '%s\n' '{"name":"context7","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.context7.com/mcp"}}'
        ;;
    esac
  else
    printf '%s\n' '{"enabled":false}'
  fi
  exit 0
fi
if [[ "${1:-}" == "mcp" && "${2:-}" == "add" ]]; then
  printf '%s\n' "$*" >>"$MOCK_CODEX_LOG"
  touch "$MOCK_STATE/${3:-}"
  exit 0
fi
exit 1
MOCK
chmod +x "$tmp/bin/codex"
cat >"$tmp/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
exit 1
MOCK
chmod +x "$tmp/bin/git"
cat >"$tmp/bin/playwright-cli" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
exit 1
MOCK
chmod +x "$tmp/bin/playwright-cli"

shared_skills="$tmp/shared-skills"
for skill in using-superpowers brainstorming caveman playwright-cli; do
  mkdir -p "$shared_skills/$skill"
  printf '%s\n' "$skill" >"$shared_skills/$skill/SKILL.md"
done
mkdir -p "$tmp/state"

MOCK_STATE="$tmp/state" MOCK_CODEX_LOG="$tmp/codex.log" \
  MOCK_FORBIDDEN_LOG="$tmp/forbidden.log" SHARED_SKILLS_ROOT="$shared_skills" \
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
  bash "$ROOT/harnesses/codex/scripts/bootstrap.sh"
MOCK_STATE="$tmp/state" MOCK_CODEX_LOG="$tmp/codex.log" \
  MOCK_FORBIDDEN_LOG="$tmp/forbidden.log" SHARED_SKILLS_ROOT="$shared_skills" \
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
  bash "$ROOT/harnesses/codex/scripts/bootstrap.sh"
grep -Fq 'mcp add serena -- serena start-mcp-server --context=codex --project-from-cwd' \
  "$tmp/codex.log"
grep -Fq 'mcp add context7 --url https://mcp.context7.com/mcp' "$tmp/codex.log"
[[ "$(wc -l <"$tmp/codex.log" | tr -d ' ')" == 2 ]]
skills_link="$tmp/home/.agents/skills"
[[ -L "$skills_link" ]]
[[ "$(readlink "$skills_link")" == "$shared_skills" ]]
for skill in using-superpowers brainstorming caveman playwright-cli; do
  [[ -f "$skills_link/$skill/SKILL.md" ]]
done
[[ ! -e "$tmp/home/.cache/claude-sbx/codex-bootstrap-v1" ]]
[[ ! -s "$tmp/forbidden.log" ]]

echo "test_codex_integrations.sh: PASS"

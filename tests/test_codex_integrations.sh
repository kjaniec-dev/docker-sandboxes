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

snapshot_discovery_entries() {
  local directory="$1"
  snapshot_discovery_tree "$directory" | LC_ALL=C sort
}

snapshot_discovery_tree() {
  local directory="$1"
  local prefix="${2:-}" entry name type
  local -a entries
  shopt -s nullglob dotglob
  entries=("$directory"/*)
  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    if [[ -L "$entry" ]]; then
      type=symlink
    elif [[ -d "$entry" ]]; then
      type=directory
    elif [[ -f "$entry" ]]; then
      type=file
    else
      type=other
    fi
    printf '%s\t%s\n' "$prefix$name" "$type"
    if [[ "$type" == directory ]]; then
      snapshot_discovery_tree "$entry" "$prefix$name/"
    fi
  done
}

assert_discovery_snapshot() {
  local expected="$1" directory="$2" actual
  actual="$(snapshot_discovery_entries "$directory")"
  [[ "$actual" == "$expected" ]] || {
    echo "bootstrap changed the skills discovery directory: $actual" >&2
    exit 1
  }
  [[ "$actual" != *$'\tsymlink'* ]] || {
    echo 'bootstrap created a skills symlink' >&2
    exit 1
  }
}

skills_dir="$tmp/home/.agents/skills"
mkdir -p "$skills_dir"
printf '%s\n' user-owned >"$skills_dir/user-skill.md"
skills_before_snapshot="$(snapshot_discovery_entries "$skills_dir")"
skills_before="$(cksum <"$skills_dir/user-skill.md")"
mkdir -p "$tmp/state"

MOCK_STATE="$tmp/state" MOCK_CODEX_LOG="$tmp/codex.log" \
  MOCK_FORBIDDEN_LOG="$tmp/forbidden.log" \
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
  bash "$ROOT/harnesses/codex/scripts/bootstrap.sh"
assert_discovery_snapshot "$skills_before_snapshot" "$skills_dir"
MOCK_STATE="$tmp/state" MOCK_CODEX_LOG="$tmp/codex.log" \
  MOCK_FORBIDDEN_LOG="$tmp/forbidden.log" \
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" \
  bash "$ROOT/harnesses/codex/scripts/bootstrap.sh"
assert_discovery_snapshot "$skills_before_snapshot" "$skills_dir"
grep -Fq 'mcp add serena -- serena start-mcp-server --context=codex --project-from-cwd' \
  "$tmp/codex.log"
grep -Fq 'mcp add context7 --url https://mcp.context7.com/mcp' "$tmp/codex.log"
[[ "$(wc -l <"$tmp/codex.log" | tr -d ' ')" == 2 ]]
[[ -d "$skills_dir" && ! -L "$skills_dir" ]]
[[ "$(cksum <"$skills_dir/user-skill.md")" == "$skills_before" ]]
[[ ! -e "$tmp/home/.cache/claude-sbx/codex-bootstrap-v1" ]]
[[ ! -s "$tmp/forbidden.log" ]]

echo "test_codex_integrations.sh: PASS"

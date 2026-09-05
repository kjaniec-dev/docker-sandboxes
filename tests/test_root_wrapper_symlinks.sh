#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/target-repo"
git init -q "$repo"
printf '.worktrees/\n' >"$repo/.gitignore"
repo="$(cd -P "$repo" && pwd)"

mkdir -p "$tmp/mock-bin"
cat >"$tmp/mock-bin/sbx" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

case "$1 ${2:-}" in
  "ls -q") exit 0 ;;
  "template ls")
    printf '%s\n' \
      'docker.io/library/claude-sbx local test claude-code-docker now' \
      'docker.io/library/codex-sbx local test codex-docker now' \
      'docker.io/library/opencode-sbx local test opencode-docker now' \
      'docker.io/library/antigravity-sbx local test shell-docker now'
    exit 0
    ;;
esac

printf 'sbx' >>"$MOCK_LOG"
for arg in "$@"; do
  printf ' %s' "$arg" >>"$MOCK_LOG"
done
printf '\n' >>"$MOCK_LOG"
MOCK
chmod +x "$tmp/mock-bin/sbx"

export MOCK_LOG="$tmp/commands.log"
ln -s "$ROOT/bin/claude-sbx" "$tmp/claude-sbx"
ln -s "$ROOT/bin/codex-sbx" "$tmp/codex-sbx"
ln -s "$ROOT/bin/opencode-sbx" "$tmp/opencode-sbx"

(
  cd "$repo"
  PATH="$tmp/mock-bin:$PATH" "$tmp/claude-sbx"
)
(
  cd "$repo"
  PATH="$tmp/mock-bin:$PATH" "$tmp/codex-sbx"
)
(
  cd "$repo"
  PATH="$tmp/mock-bin:$PATH" "$tmp/opencode-sbx"
)

grep -Fq -- "--kit $ROOT/harnesses/claude-code/kit claude $repo $ROOT:ro" "$MOCK_LOG"
grep -Fq -- "--kit $ROOT/harnesses/codex/kit codex $repo $ROOT:ro" "$MOCK_LOG"
grep -Fq -- "--kit $ROOT/harnesses/opencode/kit opencode $repo $ROOT:ro" "$MOCK_LOG"

ln -s "$ROOT/bin/antigravity-sbx" "$tmp/antigravity-sbx"

(
  cd "$repo"
  PATH="$tmp/mock-bin:$PATH" "$tmp/antigravity-sbx"
)

grep -Fq -- "--kit $ROOT/harnesses/antigravity-cli/kit antigravity $repo $ROOT:ro" "$MOCK_LOG"

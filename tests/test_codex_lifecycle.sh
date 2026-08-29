#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
git init -q "$repo"
repo="$(cd -P "$repo" && pwd)"
source "$ROOT/harnesses/codex/bin/codex-sbx"

if ensure_worktrees_ignored "$repo"; then
  echo "Codex worktree guard accepted an unignored directory" >&2
  exit 1
fi

printf '.worktrees/\n' >"$repo/.gitignore"
ensure_worktrees_ignored "$repo"

mounts="$(workspace_mounts "$repo")"
[[ "$mounts" == "$repo
$ROOT:ro" ]] || {
  echo "unexpected Codex workspace mounts: $mounts" >&2
  exit 1
}

mkdir -p "$tmp/bin"
cat >"$tmp/bin/sbx" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "ls" && "$2" == "-q" ]]; then
  exit 0
fi

if [[ "$1" == "template" && "$2" == "ls" ]]; then
  printf '%s\n' 'docker.io/library/codex-sbx local 753b231c8eaa codex-docker 2 days ago'
  exit 0
fi

printf 'sbx' >>"$MOCK_LOG"
for arg in "$@"; do
  printf ' %s' "$arg" >>"$MOCK_LOG"
done
printf '\n' >>"$MOCK_LOG"
MOCK
chmod +x "$tmp/bin/sbx"

name="$(sandbox_name_for_repo "$repo")"
export MOCK_LOG="$tmp/commands.log"
(
  cd "$repo"
  PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/codex/bin/codex-sbx'; main"
)

grep -Fq "sbx create --name $name --template codex-sbx:local --kit $ROOT/harnesses/codex/kit codex $repo $ROOT:ro" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}
grep -Fq "sbx exec $name bash $ROOT/harnesses/codex/scripts/bootstrap.sh" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}
grep -Fq "sbx run --name $name" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
git init -q "$repo"
repo="$(cd -P "$repo" && pwd)"
source "$ROOT/harnesses/antigravity-cli/bin/antigravity-sbx"

if ensure_worktrees_ignored "$repo"; then
  echo "Antigravity worktree guard accepted an unignored directory" >&2
  exit 1
fi

printf '.worktrees/\n' >"$repo/.gitignore"
ensure_worktrees_ignored "$repo"

mounts="$(workspace_mounts "$repo")"
[[ "$mounts" == "$repo
$ROOT:ro" ]] || {
  echo "unexpected Antigravity workspace mounts: $mounts" >&2
  exit 1
}

mkdir -p "$tmp/bin"
cat >"$tmp/bin/sbx" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "ls" && "$2" == "-q" ]]; then
  if [[ "${MOCK_EXISTING:-0}" == 1 ]]; then
    printf '%s\n' "$MOCK_SANDBOX_NAME"
  fi
  exit 0
fi

if [[ "$1" == "template" && "$2" == "ls" ]]; then
  printf '%s\n' 'docker.io/library/antigravity-sbx local 753b231c8eaa shell-docker 2 days ago'
  exit 0
fi

printf 'sbx' >>"$MOCK_LOG"
for arg in "$@"; do
  printf ' %s' "$arg" >>"$MOCK_LOG"
done
printf '\n' >>"$MOCK_LOG"

if [[ "$1" == "exec" && "${3:-}" == "test" && "${MOCK_MARKER_PRESENT:-0}" != 1 ]]; then
  exit 1
fi
MOCK
chmod +x "$tmp/bin/sbx"

name="$(sandbox_name_for_repo "$repo")"
export MOCK_LOG="$tmp/commands.log"
export MOCK_SANDBOX_NAME="$name"
(
  cd "$repo"
  PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/antigravity-cli/bin/antigravity-sbx'; main --model test-model"
)

grep -Fq "sbx create --name $name --template antigravity-sbx:local --kit $ROOT/harnesses/antigravity-cli/kit shell $repo $ROOT:ro" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}
grep -Fq "sbx exec $name bash $ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}
grep -Fq "sbx exec -it $name agy --model test-model" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}

export MOCK_EXISTING=1
export MOCK_MARKER_PRESENT=0
(
  cd "$repo"
  PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/antigravity-cli/bin/antigravity-sbx'; main --session resumed"
)

grep -Fq "sbx exec $name test -f" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}
[[ "$(grep -Fc "sbx exec $name bash $ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh" "$MOCK_LOG")" == 2 ]] || {
  cat "$MOCK_LOG" >&2
  exit 1
}
grep -Fq "sbx exec -it $name agy --session resumed" "$MOCK_LOG" || {
  cat "$MOCK_LOG" >&2
  exit 1
}

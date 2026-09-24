#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export XDG_CACHE_HOME="$tmp/cache"
export MOCK_STORE="$tmp/shared skills"
export MOCK_LOG="$tmp/commands.jsonl"
export MOCK_CWD_LOG="$tmp/cwd.log"
export MOCK_EXISTING=0
export MOCK_CREATE_STATUS=0
export HOME="$tmp/home"
mkdir -p "$HOME"

source "$ROOT/bin/claude-sbx"
# shellcheck source=shared/skills.sh
source "$ROOT/shared/skills.sh"
for skill in "${SUPERPOWERS_SKILLS[@]}" caveman playwright-cli; do
  mkdir -p "$MOCK_STORE/$skill"
  touch "$MOCK_STORE/$skill/SKILL.md"
done
printf '%s\n' "$CAVEMAN_REVISION" >"$MOCK_STORE/caveman/.sbx-revision"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/sbx" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >>"$MOCK_LOG"
case "$1 $2" in
  'skills ls')
    [[ "$3" == --json ]]
    jq -cn --arg store "$MOCK_STORE" '{store:$store,skills:[]}' ;;
  'skills add') exit 91 ;;
  'ls --json')
    if [[ "$MOCK_EXISTING" == 1 ]]; then
      jq -cn --arg name "$MOCK_NAME" '{sandboxes:[{name:$name}]}'
    else
      jq -cn '{sandboxes:[]}'
    fi ;;
  'create --name')
    printf '%s\n' "$PWD" >>"$MOCK_CWD_LOG"
    [[ "$MOCK_CREATE_STATUS" == 0 ]] || exit "$MOCK_CREATE_STATUS" ;;
  'run --name') printf '%s\n' "$PWD" >>"$MOCK_CWD_LOG" ;;
  'env create')
    echo 'Claude launcher must not use sbx env create' >&2
    exit 92 ;;
  *)
    echo "Unexpected sbx operation: $*" >&2
    exit 92
    ;;
esac
MOCK
chmod +x "$tmp/bin/sbx"
export PATH="$tmp/bin:$PATH"

repo="$tmp/repo with spaces"
git init -q "$repo"
repo="$(cd -P "$repo" && pwd)"
printf '.worktrees/\n' >"$repo/.gitignore"
nested="$repo/src/nested"
mkdir -p "$nested"
name="$(sandbox_name_for_repo "$repo")"
export MOCK_NAME="$name"

: >"$MOCK_LOG"
: >"$MOCK_CWD_LOG"
(
  cd "$nested"
  "$ROOT/bin/claude-sbx" --model sonnet --prompt 'hello "world"'
)
jq -se --arg name "$name" --arg kit "$ROOT/harnesses/claude-code/kit" --arg repo "$repo" '
  length == 4 and
  .[0] == ["skills", "ls", "--json"] and
  .[1] == ["ls", "--json"] and
  .[2] == ["create", "--name", $name, "--skills=readonly", $kit, $repo] and
  .[3] == ["run", "--name", $name, "--", "--model", "sonnet", "--prompt", "hello \"world\""]
' "$MOCK_LOG" >/dev/null
mapfile -t mock_cwds <"$MOCK_CWD_LOG"
[[ "${#mock_cwds[@]}" == 2 ]]
[[ "${mock_cwds[0]}" == "$repo" && "${mock_cwds[1]}" == "$repo" ]]
[[ ! -e "$HOME/.sbxenv.yaml" ]]

: >"$MOCK_LOG"
: >"$MOCK_CWD_LOG"
(
  export MOCK_EXISTING=1
  cd "$repo"
  "$ROOT/bin/claude-sbx" --model haiku
)
jq -se --arg name "$name" '
  length == 3 and
  .[0] == ["skills", "ls", "--json"] and
  .[1] == ["ls", "--json"] and
  .[2] == ["run", "--name", $name, "--", "--model", "haiku"]
' "$MOCK_LOG" >/dev/null
[[ "$(wc -l <"$MOCK_CWD_LOG" | tr -d ' ')" == 1 ]]
[[ ! -e "$HOME/.sbxenv.yaml" ]]

guard_repo="$tmp/unguarded"
git init -q "$guard_repo"
: >"$MOCK_LOG"
status=0
(
  cd "$guard_repo"
  "$ROOT/bin/claude-sbx"
) 2>/dev/null || status=$?
[[ "$status" == 3 ]]
[[ ! -s "$MOCK_LOG" ]]

: >"$MOCK_LOG"
: >"$MOCK_CWD_LOG"
status=0
(
  export MOCK_CREATE_STATUS=17
  cd "$repo"
  "$ROOT/bin/claude-sbx" --model sonnet
) 2>/dev/null || status=$?
[[ "$status" == 17 ]]
jq -se --arg name "$name" --arg kit "$ROOT/harnesses/claude-code/kit" --arg repo "$repo" '
  length == 3 and
  .[0] == ["skills", "ls", "--json"] and
  .[1] == ["ls", "--json"] and
  .[2] == ["create", "--name", $name, "--skills=readonly", $kit, $repo]
' "$MOCK_LOG" >/dev/null
[[ "$(wc -l <"$MOCK_CWD_LOG" | tr -d ' ')" == 1 ]]

echo 'test_claude_native_lifecycle.sh: PASS'

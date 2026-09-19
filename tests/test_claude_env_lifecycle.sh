#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export XDG_CACHE_HOME="$tmp/cache"
export MOCK_STORE="$tmp/shared skills"
export MOCK_LOG="$tmp/commands.jsonl"
export MOCK_CALL_LOG="$tmp/calls.jsonl"
export MOCK_CWD_LOG="$tmp/cwd.log"
export MOCK_FORBIDDEN_LOG="$tmp/forbidden.log"
home="$tmp/home"
mkdir -p "$home"
export HOME="$home"
agent_path="$ROOT/harnesses/claude-code/kit"
printf '%s\n' \
  'schemaVersion: "1"' \
  "agent: $agent_path" \
  'workspace: ${{ env.projectDir }}' \
  'skills: readonly' >"$HOME/.sbxenv.yaml"
export MOCK_ENV_FILE="$HOME/.sbxenv.yaml"
export MOCK_EXPECTED_AGENT="$agent_path"
export MOCK_ENV_CHECKSUM="$(cksum <"$MOCK_ENV_FILE")"

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
jq -cn --args '$ARGS.positional' -- "$@" >>"$MOCK_CALL_LOG"
case "$1 $2" in
  'skills ls')
    [[ "$3" == --json ]]
    if [[ "${MOCK_SKILLS_STATUS:-0}" != 0 ]]; then
      exit "$MOCK_SKILLS_STATUS"
    fi
    if [[ "${MOCK_SKILLS_OUTPUT:-valid}" == invalid ]]; then
      printf '%s\n' '{"store":'
    else
      jq -cn --arg store "$MOCK_STORE" '{store:$store,skills:[]}'
    fi ;;
  'skills add') exit 91 ;;
  'env create')
    printf '%s\n' "$PWD" >>"$MOCK_CWD_LOG"
    [[ -f "$MOCK_ENV_FILE" ]]
    [[ "$(cksum <"$MOCK_ENV_FILE")" == "$MOCK_ENV_CHECKSUM" ]]
    grep -Fqx 'schemaVersion: "1"' "$MOCK_ENV_FILE"
    grep -Fqx -- "agent: $MOCK_EXPECTED_AGENT" "$MOCK_ENV_FILE"
    grep -Fqx 'workspace: ${{ env.projectDir }}' "$MOCK_ENV_FILE"
    grep -Fqx 'skills: readonly' "$MOCK_ENV_FILE"
    jq -cn --args '$ARGS.positional' -- "$@" >>"$MOCK_LOG"
    [[ "${MOCK_ENV_STATUS:-0}" == 0 ]] || exit "$MOCK_ENV_STATUS" ;;
  'run --name')
    printf '%s\n' "$PWD" >>"$MOCK_CWD_LOG"
    jq -cn --args '$ARGS.positional' -- "$@" >>"$MOCK_LOG" ;;
  'template ls')
    printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
    jq -cn '{images:[{repository:"docker.io/library/claude-sbx",tag:"local"}]}' ;;
  'ls --json')
    printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
    printf '%s\n' '{"sandboxes":[]}' ;;
  'create --name')
    printf '%s\n' "$*" >>"$MOCK_FORBIDDEN_LOG"
    [[ "${MOCK_ENV_STATUS:-0}" == 0 ]] || exit "$MOCK_ENV_STATUS" ;;
  *)
    echo "Unexpected sbx operation: $*" >&2
    exit 92
    ;;
esac
MOCK
chmod +x "$tmp/bin/sbx"
export PATH="$tmp/bin:$PATH"

declare -F claude_env_main >/dev/null 2>&1

repo="$tmp/repo with spaces"
git init -q "$repo"
repo="$(cd -P "$repo" && pwd)"
printf '.worktrees/\n' >"$repo/.gitignore"
nested="$repo/src/nested"
mkdir -p "$nested"
name="$(sandbox_name_for_repo "$repo")"

: >"$MOCK_LOG"
: >"$MOCK_CALL_LOG"
: >"$MOCK_CWD_LOG"
: >"$MOCK_FORBIDDEN_LOG"
caller_pwd="$PWD"
(
  cd "$nested"
  before_pwd="$PWD"
  claude_env_main --model sonnet --prompt 'hello "world"'
  [[ "$PWD" == "$before_pwd" ]]
)
[[ "$PWD" == "$caller_pwd" ]]
jq -se --arg name "$name" --arg store "$MOCK_STORE" '
  length == 2 and
  .[0] == ["env", "create", "--auto-approve", "--name", $name] and
  .[1] == ["run", "--name", $name, "--", "--model", "sonnet", "--prompt", "hello \"world\""] and
  all(.[]; (tostring | contains($store) | not))
' "$MOCK_LOG" >/dev/null
mapfile -t mock_cwds <"$MOCK_CWD_LOG"
[[ "${#mock_cwds[@]}" == 2 ]]
[[ "${mock_cwds[0]}" == "$repo" && "${mock_cwds[1]}" == "$repo" ]]
[[ ! -s "$MOCK_FORBIDDEN_LOG" ]]
[[ "$(cksum <"$MOCK_ENV_FILE")" == "$MOCK_ENV_CHECKSUM" ]]

: >"$MOCK_LOG"
: >"$MOCK_CALL_LOG"
: >"$MOCK_CWD_LOG"
: >"$MOCK_FORBIDDEN_LOG"
status=0
(
  export MOCK_SKILLS_STATUS=17
  cd "$nested"
  claude_env_main --model sonnet
) 2>/dev/null || status=$?
[[ "$status" != 0 ]]
jq -se 'length == 1 and .[0] == ["skills", "ls", "--json"]' "$MOCK_CALL_LOG" >/dev/null
[[ ! -s "$MOCK_LOG" ]]
[[ ! -s "$MOCK_CWD_LOG" ]]
[[ ! -s "$MOCK_FORBIDDEN_LOG" ]]

: >"$MOCK_LOG"
: >"$MOCK_CALL_LOG"
: >"$MOCK_CWD_LOG"
: >"$MOCK_FORBIDDEN_LOG"
status=0
(
  export MOCK_SKILLS_OUTPUT=invalid
  cd "$nested"
  claude_env_main --model sonnet
) 2>/dev/null || status=$?
[[ "$status" != 0 ]]
jq -se 'length == 1 and .[0] == ["skills", "ls", "--json"]' "$MOCK_CALL_LOG" >/dev/null
[[ ! -s "$MOCK_LOG" ]]
[[ ! -s "$MOCK_CWD_LOG" ]]
[[ ! -s "$MOCK_FORBIDDEN_LOG" ]]

guard_repo="$tmp/unguarded"
git init -q "$guard_repo"
: >"$MOCK_LOG"
: >"$MOCK_FORBIDDEN_LOG"
status=0
(
  cd "$guard_repo"
  claude_env_main
) 2>/dev/null || status=$?
[[ "$status" == 3 ]]
[[ ! -s "$MOCK_LOG" ]]
[[ "$(cksum <"$MOCK_ENV_FILE")" == "$MOCK_ENV_CHECKSUM" ]]

rm "$MOCK_ENV_FILE"
: >"$MOCK_LOG"
: >"$MOCK_FORBIDDEN_LOG"
env_error="$tmp/missing-env.stderr"
status=0
(
  cd "$repo"
  claude_env_main --model sonnet
) 2>"$env_error" || status=$?
[[ "$status" == 1 ]]
grep -Fq "$MOCK_ENV_FILE" "$env_error"
[[ ! -s "$MOCK_LOG" ]]
[[ ! -s "$MOCK_FORBIDDEN_LOG" ]]
printf '%s\n' \
  'schemaVersion: "1"' \
  "agent: $agent_path" \
  'workspace: ${{ env.projectDir }}' \
  'skills: readonly' >"$MOCK_ENV_FILE"

: >"$MOCK_LOG"
: >"$MOCK_FORBIDDEN_LOG"
status=0
(
  export MOCK_ENV_STATUS=17
  cd "$repo"
  claude_env_main --model sonnet
) 2>/dev/null || status=$?
[[ "$status" == 17 ]]
[[ "$(wc -l <"$MOCK_LOG" | tr -d ' ')" == 1 ]]
! jq -e '.[0] == "run"' "$MOCK_LOG" >/dev/null
[[ "$(cksum <"$MOCK_ENV_FILE")" == "$MOCK_ENV_CHECKSUM" ]]

echo 'test_claude_env_lifecycle.sh: PASS'

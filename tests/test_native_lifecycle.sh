#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache"
export MOCK_STATE="$tmp/sandbox-name"
export MOCK_STORE="$tmp/shared skills" MOCK_LOG="$tmp/commands.jsonl"
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
case "$1 $2" in
  'template ls')
    [[ "$3" == --json ]]
    jq -cn --arg repo "docker.io/library/$MOCK_AGENT-sbx" \
      '{images:[{repository:$repo,tag:"local",id:"abc",flavor:"shell-docker"}]}' ;;
  'skills ls') jq -cn --arg store "$MOCK_STORE" '{store:$store,skills:[]}' ;;
  'ls --json')
    if [[ -s "$MOCK_STATE" ]]; then
      jq -cn --arg name "$(cat "$MOCK_STATE")" '{sandboxes:[{name:$name}]}'
    else
      echo '{"sandboxes":[]}'
    fi ;;
  'create --name')
    jq -cn --args '$ARGS.positional' -- "$@" >>"$MOCK_LOG"
    [[ "${MOCK_ENV_STATUS:-0}" == 0 ]] || exit "$MOCK_ENV_STATUS"
    printf '%s\n' "$3" >"$MOCK_STATE" ;;
  'run --name') jq -cn --args '$ARGS.positional' -- "$@" >>"$MOCK_LOG" ;;
  *) echo "Unexpected sbx operation: $*" >&2; exit 92 ;;
esac
MOCK
chmod +x "$tmp/bin/sbx"
export PATH="$tmp/bin:$PATH"
repo="$tmp/repo with 'quotes\" and spaces"
git init -q "$repo"
repo="$(cd -P "$repo" && pwd)"
printf '.worktrees/\n' >"$repo/.gitignore"
for agent in claude codex opencode agy junie; do
  export MOCK_AGENT="$agent"
  : >"$MOCK_STATE"
  : >"$MOCK_LOG"
  ln -s "$ROOT/bin/$agent-sbx" "$tmp/bin/$agent-sbx"
  # Initial launch and reuse through a PATH symlink must resolve the same kit.
  for launcher in "$ROOT/bin/$agent-sbx" "$tmp/bin/$agent-sbx"; do
    (
      cd "$repo"
      "$launcher" --prompt 'hello "world"'
    )
  done
  jq -se --arg repo "$repo" --arg root "$ROOT" --arg store "$MOCK_STORE" --arg agent "$agent" '
    def option($flag): . as $a | index($flag) as $i | $a[$i+1];
    def arg($flag; $prefix): . as $a | range(0; length-1) as $i |
      select($a[$i] == $flag and ($a[$i+1] | startswith($prefix + "="))) |
      $a[$i+1] | ltrimstr($prefix + "=") ;
    length == 3 and .[1] == .[2] and
    (.[0] | .[0:2] == ["create","--name"]) and
    (.[0] | option("--template")) == ($agent + "-sbx:local") and
    .[0][-3:] == [$repo, ($root + ":ro"), $store] and
    (.[0][-4] | startswith($root + "/harnesses/")) and
    (.[0] | arg("--kit-arg";"harness_root")) == $root and
    (.[0] | arg("--kit-arg";"skills_root")) == $store and
    (.[0] | option("--name")) == .[1][2] and
    (.[1][2] | startswith($agent + "-repo-with-quotes-and-spaces-")) and
    .[1][-3:] == ["--","--prompt","hello \"world\""] and
    (if $agent == "junie" then .[1][3:5] == ["--env","JUNIE_API_KEY="] else .[1][3] == "--" end)
  ' "$MOCK_LOG" >/dev/null
  : >"$MOCK_STATE"
  # Provision failure must stop before attachment, even with an existing name.
  : >"$MOCK_LOG"
  status=0
  (
    cd "$repo"
    MOCK_ENV_STATUS=17 "$ROOT/bin/$agent-sbx"
  ) || status=$?
  [[ "$status" == 17 && "$(wc -l <"$MOCK_LOG" | tr -d ' ')" == 1 ]]
  guard_repo="$tmp/unguarded-$agent"
  git init -q "$guard_repo"
  status=0
  (
    cd "$guard_repo"
    "$ROOT/bin/$agent-sbx"
  ) 2>/dev/null || status=$?
  [[ "$status" == 3 ]]
done
# A key is a session override, never a creation argument.
: >"$MOCK_STATE"
: >"$MOCK_LOG"
(
  cd "$repo"
  JUNIE_API_KEY=test-key "$ROOT/bin/junie-sbx"
)
jq -se '.[1][3:5] == ["--env","JUNIE_API_KEY=test-key"] and
  (.[0] | tostring | contains("test-key") | not)' "$MOCK_LOG" >/dev/null
# Harness itself as target: never duplicate its mount.
: >"$MOCK_STATE"
: >"$MOCK_LOG"
(
  cd "$ROOT"
  "$ROOT/bin/junie-sbx"
)
jq -se --arg root "$ROOT" --arg store "$MOCK_STORE" '.[0][-2:] == [$root,$store] and (.[0] | index($root + ":ro")) == null' "$MOCK_LOG" >/dev/null
echo 'test_native_lifecycle.sh: PASS'

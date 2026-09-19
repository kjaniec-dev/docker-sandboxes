#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/claude-sbx"
for helper in sandbox_name_for_repo repo_root_from_cwd ensure_worktrees_ignored; do
  declare -F "$helper" >/dev/null || {
    echo "missing shared launcher helper: $helper" >&2
    exit 1
  }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache"
export MOCK_STORE="$tmp/shared skills"
export MOCK_LOG="$tmp/commands.jsonl"
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
  'ls --json') printf '%s\n' '{"sandboxes":[]}' ;;
  'template ls')
    jq -cn '{images:[{repository:"docker.io/library/codex-sbx",tag:"local"}]}' ;;
  'create --name'|'run --name') ;;
  *)
    echo "Unexpected sbx operation: $*" >&2
    exit 92
    ;;
esac
MOCK
chmod +x "$tmp/bin/sbx"
export PATH="$tmp/bin:$PATH"

repo="$tmp/repo"
git init -q "$repo"
printf '.worktrees/\n' >"$repo/.gitignore"
repo="$(cd -P "$repo" && pwd)"
name="$(printf '%s' "$repo" | shasum -a 256 | awk '{print "codex-repo-" substr($1,1,8)}')"
: >"$MOCK_LOG"
(
  cd "$repo"
  "$ROOT/bin/codex-sbx" --prompt 'hello "world"'
)
jq -se --arg name "$name" --arg root "$ROOT" --arg repo "$repo" \
  --arg kit "$ROOT/harnesses/codex/kit" --arg store "$MOCK_STORE" '
  map(select(.[0:2] == ["create", "--name"])) as $create |
  map(select(.[0:2] == ["run", "--name"])) as $run |
  $create == [["create", "--name", $name, "--skills=readonly", "--kit-arg", ("harness_root=" + $root), $kit, $repo, ($root + ":ro")]] and
  $run == [["run", "--name", $name, "--", "--approve-for-me", "--prompt", "hello \"world\""]] and
  (map(select(.[0:2] == ["template", "ls"])) | length) == 0 and
  all(.[]; (tostring | contains($store) | not))
' "$MOCK_LOG" >/dev/null
echo 'test_template_exists.sh: PASS'

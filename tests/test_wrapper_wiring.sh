#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grep -Fq 'FROM docker/sandbox-templates:claude-code-docker' "$ROOT/harnesses/claude-code/Dockerfile"
grep -Fq 'COPY harnesses/claude-code/scripts/bootstrap.sh /usr/local/lib/claude-sbx/bootstrap.sh' \
  "$ROOT/harnesses/claude-code/Dockerfile"
grep -Fq 'TEMPLATE="claude-sbx:local"' "$ROOT/harnesses/claude-code/bin/claude-code-sbx"
grep -Fq 'FROM docker/sandbox-templates:codex-docker' "$ROOT/harnesses/codex/Dockerfile"
grep -Fq 'codex-sbx:local' "$ROOT/harnesses/codex/bin/codex-sbx"
grep -Fq 'harnesses/codex' "$ROOT/bin/codex-sbx"
grep -Fq 'FROM docker/sandbox-templates:opencode-docker' "$ROOT/harnesses/opencode/Dockerfile"
grep -Fq 'opencode-sbx:local' "$ROOT/harnesses/opencode/bin/opencode-sbx"
grep -Fq 'harnesses/opencode' "$ROOT/bin/opencode-sbx"
grep -Fq 'harnesses/opencode/Dockerfile' "$ROOT/bin/opencode-sbx-rebuild"
grep -Fq 'FROM docker/sandbox-templates:shell-docker' "$ROOT/harnesses/antigravity-cli/Dockerfile"
grep -Fq 'agy-sbx:local' "$ROOT/harnesses/antigravity-cli/bin/agy-sbx"
grep -Fq 'harnesses/antigravity-cli' "$ROOT/bin/agy-sbx"
grep -Fq 'harnesses/antigravity-cli/Dockerfile' "$ROOT/bin/agy-sbx-rebuild"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

docker_context_copy() {
  local source="$1" image_id
  image_id="$(printf 'FROM scratch\nCOPY %s /probe\n' "$source" |
    docker build --quiet --no-cache -f - "$ROOT" 2>"$tmp/docker-build.stderr")" || return
  docker image rm "$image_id" >/dev/null
}

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  for source in \
    shared/install-system-toolchain.sh \
    shared/install-user-toolchain.sh \
    harnesses/claude-code/scripts/bootstrap.sh; do
    docker_context_copy "$source" || {
      printf 'Docker context omitted required file: %s\n' "$source" >&2
      exit 1
    }
  done

  for source in \
    shared/launcher.sh \
    shared/rebuild.sh \
    shared/skills.sh \
    shared/verify-browser.sh \
    shared/verify-toolchain.sh \
    harnesses/claude-code/Dockerfile \
    harnesses/claude-code/kit/spec.yaml \
    harnesses/claude-code/scripts/verify.sh \
    harnesses/claude-code/bin/claude-code-sbx \
    harnesses/codex/Dockerfile \
    .git \
    .superpowers/sdd/2026-09-19-sbx-043-claude/task-4-rereview-report.md; do
    if docker_context_copy "$source"; then
      printf 'Docker context unexpectedly includes: %s\n' "$source" >&2
      exit 1
    fi
  done
else
  echo 'test_wrapper_wiring.sh: SKIP Docker context probe (Docker daemon unavailable)'
fi

export XDG_CACHE_HOME="$tmp/cache"
export MOCK_STORE="$tmp/shared skills"
export MOCK_LOG="$tmp/commands.jsonl"
export HOME="$tmp/home"
mkdir -p "$HOME"
agent_path="$ROOT/harnesses/claude-code/kit"
printf '%s\n' \
  'schemaVersion: "1"' \
  "agent: $agent_path" \
  'workspace: ${{ env.projectDir }}' \
  'skills: readonly' >"$HOME/.sbxenv.yaml"

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
    jq -cn '{images:[
      {repository:"docker.io/library/codex-sbx",tag:"local"},
      {repository:"docker.io/library/claude-sbx",tag:"local"}
    ]}' ;;
  'create --name'|'env create'|'run --name') ;;
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
codex_name="$(printf '%s' "$repo" | shasum -a 256 | awk '{print "codex-repo-" substr($1,1,8)}')"

: >"$MOCK_LOG"
(
  cd "$repo"
  "$ROOT/bin/codex-sbx" --prompt 'hello "world"'
)
jq -se --arg name "$codex_name" --arg root "$ROOT" --arg repo "$repo" \
  --arg kit "$ROOT/harnesses/codex/kit" --arg store "$MOCK_STORE" '
  map(select(.[0:2] == ["create", "--name"])) as $create |
  map(select(.[0:2] == ["run", "--name"])) as $run |
  ([.[] | select((.[0:2] == ["create", "--name"]) or (.[0:2] == ["run", "--name"]))]) == ($create + $run) and
  $create == [["create", "--name", $name, "--skills=readonly", "--kit-arg", ("harness_root=" + $root), $kit, $repo, ($root + ":ro")]] and
  $run == [["run", "--name", $name, "--", "--prompt", "hello \"world\""]] and
  (map(select(.[0:2] == ["template", "ls"])) | length) == 0 and
  all(.[]; (tostring | contains($store) | not))
' "$MOCK_LOG" >/dev/null

: >"$MOCK_LOG"
claude_name="$(printf '%s' "$repo" | shasum -a 256 | awk '{print "claude-repo-" substr($1,1,8)}')"
(
  cd "$repo"
  "$ROOT/bin/claude-sbx" --model sonnet --prompt 'hello "world"'
)
jq -se --arg name "$claude_name" --arg store "$MOCK_STORE" '
  map(select(.[0:2] == ["env", "create"])) as $create |
  map(select(.[0:2] == ["run", "--name"])) as $run |
  $create == [["env", "create", "--auto-approve", "--name", $name]] and
  $run == [["run", "--name", $name, "--", "--model", "sonnet", "--prompt", "hello \"world\""]] and
  (map(select(.[0:2] == ["template", "ls"])) | length) == 0 and
  (map(select(.[0:2] == ["create", "--name"])) | length) == 0 and
  (map(select(.[0:2] == ["ls", "--json"])) | length) == 0 and
  all(.[]; (tostring | contains($store) | not))
' "$MOCK_LOG" >/dev/null

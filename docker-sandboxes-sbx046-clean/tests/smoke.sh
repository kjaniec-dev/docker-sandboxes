#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="${1:-}"
[[ -n "$agent" ]] || { echo "usage: $0 <agent>" >&2; exit 2; }
profile="${SBX_PROFILE:-personal}"

case "$profile:$agent" in
  personal:claude|personal:codex|personal:opencode|personal:antigravity|personal:junie) ;;
  client:claude|client:copilot) ;;
  *) echo "smoke: unsupported $profile/$agent" >&2; exit 2 ;;
esac

command -v sbx >/dev/null 2>&1 || { echo "smoke: sbx is required" >&2; exit 1; }

repo="$(mktemp -d)"
git -C "$repo" init -q
printf '.worktrees/\n' > "$repo/.gitignore"
printf '# SBX smoke project\n' > "$repo/README.md"

agent_env="$ROOT/env/$profile/$agent.sbxenv.yaml"
common_env="$ROOT/env/common.sbxenv.yaml"
name="smoke-$profile-$agent"
files=("$agent_env" "$common_env")

local_overlay="$HOME/.config/docker-sandboxes/$profile.sbxenv.yaml"
[[ -f "$local_overlay" ]] && files+=("$local_overlay")

args=(--env-arg "workspace=$repo")
if [[ "$profile:$agent" == client:claude ]]; then
  : "${ANTHROPIC_VERTEX_PROJECT_ID:?Set ANTHROPIC_VERTEX_PROJECT_ID}"
  : "${CLOUD_ML_REGION:?Set CLOUD_ML_REGION}"
  args+=(
    --env-arg "vertexProject=$ANTHROPIC_VERTEX_PROJECT_ID"
    --env-arg "vertexRegion=$CLOUD_ML_REGION"
  )
fi

cleanup() {
  sbx env rm "${files[@]}" --name "$name" "${args[@]}" --force >/dev/null 2>&1 || true
  rm -rf "$repo"
}
trap cleanup EXIT

sbx env run "${files[@]}" --name "$name" --detached --auto-approve "${args[@]}"

sbx exec "$name" bash -lc '
  set -e
  git --version
  node --version
  python3 --version
  uv --version
  go version
  java --version
  mvn --version
  gradle --version
  serena --help >/dev/null
  playwright-cli --help >/dev/null
  command -v docker >/dev/null
'

sbx run --name "$name" -- --help >/dev/null 2>&1 || true
sbx exec "$name" git status --short >/dev/null

if [[ "${SBX_SMOKE_MODEL:-0}" == 1 ]]; then
  case "$agent" in
    codex) sbx run --name "$name" -- exec "Reply with only: OK" ;;
    claude) sbx run --name "$name" -- -p "Reply with only: OK" ;;
    opencode) sbx run --name "$name" -- run "Reply with only: OK" ;;
    *) echo "smoke: model smoke for $agent remains interactive; verify manually" ;;
  esac
fi

echo "smoke: PASS $profile/$agent"

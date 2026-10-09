#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
agent="${1:-}"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}/docker-sandboxes"
profile="${SBX_PROFILE:-}"
if [[ -z "$profile" && -f "$config_root/profile" ]]; then
  profile="$(tr -d '[:space:]' < "$config_root/profile")"
fi
profile="${profile:-personal}"
case "$profile:$agent" in
  personal:claude|personal:codex|personal:opencode|personal:antigravity|personal:junie|client:claude|client:copilot) ;;
  *) echo "usage: SBX_PROFILE=<personal|client> $0 <agent>" >&2; exit 2 ;;
esac
command -v sbx >/dev/null || { echo "smoke: SBX is required" >&2; exit 1; }
export SBX_KIT_BUILDER="${SBX_KIT_BUILDER-sandbox}"
if [[ "$profile:$agent" == client:claude ]]; then
  : "${ANTHROPIC_VERTEX_PROJECT_ID:?Set ANTHROPIC_VERTEX_PROJECT_ID}"
  : "${CLOUD_ML_REGION:?Set CLOUD_ML_REGION}"
fi
repo="$(mktemp -d)"
repo="$(cd "$repo" && pwd -P)"
name="smoke-$profile-$agent-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:10])')"
logs="${SBX_SMOKE_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$logs"
files=("$ROOT/env/$profile/$agent.sbxenv.yaml" "$ROOT/env/common.sbxenv.yaml")
[[ ! -f "$config_root/$profile.sbxenv.yaml" ]] || files+=("$config_root/$profile.sbxenv.yaml")
args=(--name "$name" --env-arg "workspace=$repo")
if [[ "$profile:$agent" == client:claude ]]; then
  args+=(--env-arg "vertexProject=$ANTHROPIC_VERTEX_PROJECT_ID" --env-arg "vertexRegion=$CLOUD_ML_REGION")
fi
owned=false
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$status" != 0 && "$owned" == true && "${SBX_SMOKE_KEEP_ON_FAILURE:-0}" == 1 ]]; then
    echo "smoke: debug sandbox retained: $name workspace=$repo logs=$logs" >&2
    exit "$status"
  fi
  if [[ "$owned" == true ]]; then
    if ! sbx env rm "${files[@]}" "${args[@]}" --force >"$logs/cleanup.log" 2>&1; then
      echo "smoke: cleanup failed; retain $name and workspace $repo (logs: $logs)" >&2
      exit 1
    fi
  fi
  rm -rf "$repo"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git -C "$repo" init -q
printf '.worktrees/\n' > "$repo/.gitignore"
mkdir "$repo/.worktrees"
printf 'def smoke_symbol():\n    return 42\n' > "$repo/main.py"
printf '# Disposable SBX smoke project\n' > "$repo/README.md"
inventory="$(sbx ls --json)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d.get("sandboxes"),list), "invalid sandbox inventory"; assert not any(s["name"]==sys.argv[1] for s in d["sandboxes"]), "smoke name occupied"' "$name" <<<"$inventory"
owned=true
echo "smoke: $profile/$agent sandbox=$name logs=$logs"
apply() { sbx env run "${files[@]}" "${args[@]}" --detached --auto-approve; }
check() {
  local stage="$1"
  local -a check_args=(exec -i "$name")
  local junie_placeholder=""
  if [[ "$agent" == junie ]]; then
    junie_placeholder="$(python3 "$ROOT/workloads/junie-dev/token-placeholder.py" "$name")"
    check_args=(env exec -i --name "$name" --env-arg "workspace=$repo"
      --env "JUNIE_API_KEY=$junie_placeholder" "${files[@]}" --)
  fi
  local vertex_placeholder=""
  if [[ "$profile:$agent" == client:claude ]]; then
    vertex_placeholder="$(python3 "$ROOT/workloads/claude-dev/token-placeholder.py" "$name" "$CLOUD_ML_REGION")"
    check_args=(env exec -i "${args[@]}" --env "ANTHROPIC_AUTH_TOKEN=$vertex_placeholder" "${files[@]}" --)
  fi
  if ! sbx "${check_args[@]}" /opt/sbx-dev/serena/bin/python - "$agent" "$repo" "$stage" "$name" \
    < "$ROOT/tests/smoke-check.py" >"$logs/$stage-check.log" 2>&1; then
    echo "smoke: $stage infrastructure check failed (logs: $logs)" >&2
    return 1
  fi
  if [[ "${SBX_SMOKE_MODEL:-0}" == 1 ]]; then
    local left=$((RANDOM % 800 + 100)) right=$((RANDOM % 800 + 100)) prompt
    local -a model_args exec_args=(exec "$name")
    prompt="Calculate $left + $right. Reply with only the decimal answer. Do not use tools."
    case "$agent" in
      codex) model_args=(codex exec --json --ephemeral "$prompt") ;;
      claude)
        if [[ "$profile" == client ]]; then
          exec_args=(env exec "${args[@]}" --env "ANTHROPIC_AUTH_TOKEN=$vertex_placeholder" "${files[@]}" --)
        fi
        model_args=(claude --dangerously-skip-permissions -p --output-format json "$prompt") ;;
      opencode) model_args=(opencode run --format json "$prompt") ;;
      antigravity) model_args=(agy -p "$prompt" --output-format json) ;;
      junie)
        exec_args=(env exec --name "$name" --env-arg "workspace=$repo"
          --env "JUNIE_API_KEY=$junie_placeholder" "${files[@]}" --)
        model_args=(junie --skip-update-check --output-format text "$prompt") ;;
      copilot) model_args=(copilot -p "$prompt" --silent) ;;
    esac
    if ! python3 - "${SBX_SMOKE_REQUEST_TIMEOUT:-180}" sbx "${exec_args[@]}" "${model_args[@]}" \
      >"$logs/$stage-model.log" 2>"$logs/$stage-model-error.log" <<'PY'
import os, signal, subprocess, sys
process = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, start_new_session=True)
try:
    status = process.wait(timeout=int(sys.argv[1]))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try: process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    status = 124
sys.exit(status if status >= 0 else 128 - status)
PY
    then
      echo "smoke: $stage model request failed (logs: $logs)" >&2
      return 1
    fi
    python3 "$ROOT/tests/model-response.py" "$agent" "$((left + right))" "$logs/$stage-model.log"
  fi
  echo "smoke: $stage passed"
}
apply >"$logs/create.log" 2>&1 || { echo "smoke: creation failed (logs: $logs)" >&2; exit 1; }
check fresh
sbx stop "$name" >"$logs/stop.log" 2>&1
apply >"$logs/restart.log" 2>&1
check restarted
sbx env rm "${files[@]}" "${args[@]}" --force >"$logs/remove.log" 2>&1
owned=false
inventory="$(sbx ls --json)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d.get("sandboxes"),list); assert not any(s["name"]==sys.argv[1] for s in d["sandboxes"]), "removed sandbox still present"' "$name" <<<"$inventory"
owned=true
apply >"$logs/recreate.log" 2>&1 || { echo "smoke: recreation failed (logs: $logs)" >&2; exit 1; }
check recreated
if [[ "${SBX_SMOKE_MODEL:-0}" == 1 ]]; then
  echo "smoke: PASS $profile/$agent infrastructure, lifecycle and authenticated model"
else
  echo "smoke: PASS $profile/$agent infrastructure and lifecycle; model authentication NOT CHECKED"
fi

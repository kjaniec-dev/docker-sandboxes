#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
offline=false
case "${1:-}" in
  '') ;;
  --offline) offline=true; shift ;;
  *) echo "usage: $0 [--offline]" >&2; exit 2 ;;
esac
[[ $# == 0 ]] || exit 2
for script in "$ROOT/bin/sbx-dev" "$ROOT/tests/validate.sh" "$ROOT/tests/smoke.sh" \
  "$ROOT/workloads/opencode-dev/run.sh"; do
  bash -n "$script"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' -v
if [[ "$offline" == true ]]; then
  echo "validate: PASS offline behavior (native builds and runtime not checked)"
  exit 0
fi
command -v sbx >/dev/null || { echo "validate: SBX 0.47.0+ is required" >&2; exit 1; }
export SBX_KIT_BUILDER="${SBX_KIT_BUILDER-sandbox}"
python3 - "$(sbx version)" <<'PY'
import re, sys
match = re.fullmatch(r"sbx version: v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][\w.+-]+)?(?:\s.*)?", sys.argv[1])
assert match and tuple(map(int, match.groups()[:3])) >= (0, 47, 0), "SBX 0.47.0+ required"
assert not (match.groups()[:3] == ("0", "47", "0") and (match[4] or "").startswith("-")), "SBX 0.47.0 release required"
PY
for kit in workloads/claude-dev workloads/opencode-dev workloads/junie-dev mixins/dev mixins/vertex; do
  echo "validate: build/inspect $kit"
  sbx kit inspect "$ROOT/$kit" --json >/dev/null
done
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
printf '.worktrees/\n' > "$tmp/.gitignore"
plan() {
  local profile="$1" agent="$2"
  shift 2
  echo "validate: plan $profile/$agent"
  sbx env plan "$ROOT/env/$profile/$agent.sbxenv.yaml" "$ROOT/env/common.sbxenv.yaml" \
    --name "validate-$profile-$agent" --env-arg "workspace=$tmp" "$@" >/dev/null
}
plan personal codex
plan personal antigravity
plan personal junie
plan personal claude
plan personal opencode
plan client copilot
plan client claude --env-arg vertexProject=validation-project --env-arg vertexRegion=us-east5
echo "validate: PASS native kits and seven environment plans"

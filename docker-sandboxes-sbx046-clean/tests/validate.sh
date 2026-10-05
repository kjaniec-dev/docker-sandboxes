#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/bin/sbx-dev"
python3 - "$ROOT/mixins/dev/configure-agent.py" <<'PYCHECK'
from pathlib import Path
import sys
path = Path(sys.argv[1])
compile(path.read_text(), str(path), "exec")
print("validate: Python syntax passed")
PYCHECK

python3 - "$ROOT" <<'PYAML'
from pathlib import Path
import sys
try:
    import yaml
except ImportError:
    print("validate: PyYAML not installed; skipping local YAML parse", file=sys.stderr)
    raise SystemExit(0)

root = Path(sys.argv[1])
for path in root.rglob("*.yaml"):
    with path.open() as stream:
        yaml.safe_load(stream)
print("validate: YAML parse passed")
PYAML

if ! command -v sbx >/dev/null 2>&1; then
  echo "validate: SKIP native SBX checks ('sbx' not installed)"
  exit 0
fi

for kit in \
  "$ROOT/workloads/claude-dev" \
  "$ROOT/workloads/opencode-dev" \
  "$ROOT/mixins/dev" \
  "$ROOT/mixins/vertex"; do
  echo "validate: sbx kit inspect $kit"
  sbx kit inspect "$kit" >/dev/null
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
printf '.worktrees/\n' > "$tmp/.gitignore"

plan() {
  local profile="$1" agent="$2"
  shift 2
  echo "validate: plan $profile/$agent"
  sbx env plan \
    "$ROOT/env/$profile/$agent.sbxenv.yaml" \
    "$ROOT/env/common.sbxenv.yaml" \
    --name "validate-$profile-$agent" \
    --env-arg "workspace=$tmp" \
    "$@" >/dev/null
}

plan personal claude
plan personal codex
plan personal opencode
plan personal antigravity
plan personal junie
plan client copilot
plan client claude \
  --env-arg vertexProject=validation-project \
  --env-arg vertexRegion=us-east5

echo "validate: PASS"

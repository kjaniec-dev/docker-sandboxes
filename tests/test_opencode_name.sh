#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/harnesses/opencode/bin/opencode-sbx"
actual="$(sandbox_name_for_repo "/Users/example/dev/projects/my_app")"
[[ "$actual" == "opencode-my-app-2ed5b256" ]] || {
  echo "unexpected OpenCode sandbox name: $actual" >&2
  exit 1
}

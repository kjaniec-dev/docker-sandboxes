#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/harnesses/antigravity-cli/bin/agy-sbx"
actual="$(sandbox_name_for_repo "/Users/example/dev/projects/my_app")"
[[ "$actual" == "agy-my-app-2ed5b256" ]] || {
  echo "unexpected Antigravity sandbox name: $actual" >&2
  exit 1
}

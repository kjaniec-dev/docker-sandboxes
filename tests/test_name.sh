#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/claude-sbx"
actual="$(sandbox_name_for_repo "/Users/example/dev/projects/my_app")"
[[ "$actual" =~ ^claude-my-app-[0-9a-f]{8}$ ]] || {
  echo "unexpected sandbox name: $actual" >&2
  exit 1
}

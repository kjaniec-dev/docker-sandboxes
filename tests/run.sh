#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_files=("$ROOT"/tests/test_*.sh)

if [[ ! -e "${test_files[0]}" ]]; then
  echo "no host-side tests found" >&2
  exit 1
fi

for test_file in "${test_files[@]}"; do
  echo "==> $(basename "$test_file")"
  bash "$test_file"
done

#!/usr/bin/env bash
set -euo pipefail

# Source the matching launcher first for ROOT and TEMPLATE.
rebuild_template() {
  local dockerfile="$1"
  local build_dir="$ROOT/.build"
  local archive="$build_dir/${TEMPLATE%:*}.tar"
  mkdir -p "$build_dir"
  docker build --pull -t "$TEMPLATE" -f "$dockerfile" "$ROOT"
  docker image save "$TEMPLATE" -o "$archive"
  sbx template rm "$TEMPLATE" >/dev/null 2>&1 || true
  sbx template load "$archive"
  printf 'Loaded Docker Sandbox template: %s\n' "$TEMPLATE"
}

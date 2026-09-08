#!/usr/bin/env bash
set -euo pipefail

# Source the matching launcher first for ROOT, TEMPLATE, and template_exists.
rebuild_template() {
  local dockerfile="$1"
  local build_dir="$ROOT/.build"
  local archive="$build_dir/${TEMPLATE%:*}.tar"
  mkdir -p "$build_dir"
  docker build --pull -t "$TEMPLATE" -f "$dockerfile" "$ROOT"
  docker image save "$TEMPLATE" -o "$archive"
  if template_exists; then
    sbx template rm "$TEMPLATE"
  fi
  sbx template load "$archive"
  printf 'Loaded Docker Sandbox template: %s\n' "$TEMPLATE"
}

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/shared/launcher.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ROOT="$tmp/harness"
repo_root="$ROOT/.worktrees/feature"
mounts=("$repo_root")
append_harness_source_mounts "$repo_root"
[[ ${#mounts[@]} -eq 3 ]]
[[ "${mounts[1]}" == "$ROOT/harnesses:ro" ]]
[[ "${mounts[2]}" == "$ROOT/shared:ro" ]]

repo_root="$tmp/external-repo"
mounts=("$repo_root")
append_harness_source_mounts "$repo_root"
[[ ${#mounts[@]} -eq 2 ]]
[[ "${mounts[1]}" == "$ROOT:ro" ]]

repo_root="$ROOT"
mounts=("$repo_root")
append_harness_source_mounts "$repo_root"
[[ ${#mounts[@]} -eq 1 ]]

echo 'test_launcher_mounts.sh: PASS'

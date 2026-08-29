#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bin/claude-sbx"

mounts="$(workspace_mounts "$ROOT")"
[[ "$mounts" == "$ROOT" ]]

other_repo="/tmp/example-repo"
mounts="$(workspace_mounts "$other_repo")"
[[ "$mounts" == "$other_repo
$ROOT:ro" ]]

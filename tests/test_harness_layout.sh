#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -x "$ROOT/bin/claude-sbx" ]] || { echo "missing executable Claude compatibility wrapper" >&2; exit 1; }
for path in \
  "$ROOT/shared/install-system-toolchain.sh" \
  "$ROOT/shared/install-user-toolchain.sh"; do
  [[ -x "$path" ]] || { echo "missing executable: $path" >&2; exit 1; }
done

grep -Fq 'FROM docker/sandbox-templates:claude-code-docker' "$ROOT/harnesses/claude-code/Dockerfile"
grep -Fq 'install-system-toolchain.sh' "$ROOT/harnesses/claude-code/Dockerfile"
grep -Fq 'install-user-toolchain.sh' "$ROOT/harnesses/claude-code/Dockerfile"

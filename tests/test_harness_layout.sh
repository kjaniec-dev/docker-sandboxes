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
grep -Fq 'FROM docker/sandbox-templates:opencode-docker' "$ROOT/harnesses/opencode/Dockerfile"
[[ -f "$ROOT/harnesses/opencode/kit/spec.yaml" ]]
[[ -x "$ROOT/harnesses/opencode/bin/opencode-sbx" ]]
[[ -x "$ROOT/harnesses/opencode/scripts/bootstrap.sh" ]]
[[ -x "$ROOT/harnesses/opencode/scripts/verify.sh" ]]
grep -Fq 'FROM docker/sandbox-templates:shell-docker' "$ROOT/harnesses/antigravity-cli/Dockerfile"
grep -Fq 'install-system-toolchain.sh' "$ROOT/harnesses/antigravity-cli/Dockerfile"
grep -Fq 'install-user-toolchain.sh' "$ROOT/harnesses/antigravity-cli/Dockerfile"
[[ -f "$ROOT/harnesses/antigravity-cli/kit/spec.yaml" ]]
[[ -x "$ROOT/harnesses/antigravity-cli/bin/agy-sbx" ]]
[[ -x "$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh" ]]
[[ -x "$ROOT/harnesses/antigravity-cli/scripts/verify.sh" ]]

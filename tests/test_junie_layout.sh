#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'FROM docker/sandbox-templates:shell-docker' "$ROOT/harnesses/junie/Dockerfile"
grep -Fq 'install-system-toolchain.sh' "$ROOT/harnesses/junie/Dockerfile"
grep -Fq 'install-user-toolchain.sh' "$ROOT/harnesses/junie/Dockerfile"
[[ -f "$ROOT/harnesses/junie/kit/spec.yaml" ]]
[[ -x "$ROOT/harnesses/junie/bin/junie-sbx" ]]
[[ -x "$ROOT/harnesses/junie/scripts/bootstrap.sh" ]]
[[ -x "$ROOT/harnesses/junie/scripts/verify.sh" ]]
[[ -x "$ROOT/bin/junie-sbx" ]]
[[ -x "$ROOT/bin/junie-sbx-rebuild" ]]
grep -Fq 'https://junie.jetbrains.com/install.sh' "$ROOT/harnesses/junie/scripts/bootstrap.sh"
grep -Fq 'mcp.context7.com/mcp' "$ROOT/harnesses/junie/scripts/bootstrap.sh"
grep -Fq 'start-mcp-server' "$ROOT/harnesses/junie/scripts/bootstrap.sh"
grep -Fq 'playwright-cli install --skills agents --global' "$ROOT/harnesses/junie/scripts/bootstrap.sh"
grep -Fq 'superpowers' "$ROOT/harnesses/junie/scripts/bootstrap.sh"
grep -Fq 'caveman' "$ROOT/harnesses/junie/scripts/bootstrap.sh"

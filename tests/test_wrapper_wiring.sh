#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grep -Fq 'FROM docker/sandbox-templates:codex-docker' "$ROOT/harnesses/codex/Dockerfile"
grep -Fq 'sbx create' "$ROOT/harnesses/codex/bin/codex-sbx"
grep -Fq 'codex-sbx:local' "$ROOT/harnesses/codex/bin/codex-sbx"
grep -Fq 'harnesses/codex' "$ROOT/bin/codex-sbx"

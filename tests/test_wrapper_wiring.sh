#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
grep -Fq 'FROM docker/sandbox-templates:codex-docker' "$ROOT/harnesses/codex/Dockerfile"
grep -Fq 'sbx create' "$ROOT/harnesses/codex/bin/codex-sbx"
grep -Fq 'codex-sbx:local' "$ROOT/harnesses/codex/bin/codex-sbx"
grep -Fq 'harnesses/codex' "$ROOT/bin/codex-sbx"
grep -Fq 'FROM docker/sandbox-templates:opencode-docker' "$ROOT/harnesses/opencode/Dockerfile"
grep -Fq 'sbx create' "$ROOT/harnesses/opencode/bin/opencode-sbx"
grep -Fq 'opencode-sbx:local' "$ROOT/harnesses/opencode/bin/opencode-sbx"
grep -Fq 'harnesses/opencode' "$ROOT/bin/opencode-sbx"
grep -Fq 'opencode-sbx:local' "$ROOT/bin/opencode-sbx-rebuild"
grep -Fq 'harnesses/opencode/Dockerfile' "$ROOT/bin/opencode-sbx-rebuild"

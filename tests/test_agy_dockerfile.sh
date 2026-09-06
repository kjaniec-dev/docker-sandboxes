#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$ROOT/harnesses/antigravity-cli/Dockerfile"

grep -Fq 'FROM docker/sandbox-templates:shell-docker' "$DOCKERFILE"
grep -Fq 'AGY_VERSION=1.1.27' "$DOCKERFILE"
grep -Fq 'AGY_BUILD=5211191891591168' "$DOCKERFILE"
grep -Fq 'f874d4f6b8a73c2df660f580f25fb656fcb6e64adbfd746e6692e837fd9a20be' "$DOCKERFILE"
grep -Fq '97fc9fe5a6067406cd02cbe4ae6e362c9623a24d33bec486911246c17ceb6a94' "$DOCKERFILE"
grep -Fq 'sha256sum -c' "$DOCKERFILE"
grep -Fq '/usr/local/bin/agy' "$DOCKERFILE"

awk '
  /^USER root$/ { root_line = NR }
  /RUN NODE_VERSION=/ { system_line = NR }
  /^USER agent$/ { agent_line = NR }
  END {
    if (!(root_line && root_line < system_line && agent_line > system_line)) {
      exit 1
    }
  }
' "$DOCKERFILE" || {
  echo "Antigravity system installer must run as root before switching to agent" >&2
  exit 1
}

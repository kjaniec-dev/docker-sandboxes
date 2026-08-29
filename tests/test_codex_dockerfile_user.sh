#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$ROOT/harnesses/codex/Dockerfile"

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
  echo "Codex system installer must run as root before switching to agent" >&2
  exit 1
}

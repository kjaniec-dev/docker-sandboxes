#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/claude-sbx
source "$ROOT/bin/claude-sbx"
# shellcheck disable=SC2329 # Called indirectly by sourced template_exists.
sbx() {
  [[ "$*" == 'template ls --json' ]] || return 90
  printf '%s\n' "$listing"
}
listing='{"images":[{"id":"abc","repository":"docker.io/library/claude-sbx","tag":"local","flavor":"claude-code-docker"}]}'
template_exists
for listing in '{"images":[]}' '{"images":[{"repository":"docker.io/library/claude-sbx","tag":"other"}]}' \
  '{"images":[{"repository":"docker.io/library/not-claude-sbx","tag":"local"}]}' '{}' 'invalid'; do
  if template_exists 2>/dev/null; then
    echo "Unexpected template match: $listing" >&2
    exit 1
  fi
done
sbx() {
  printf '{"images":[]}\n'
  return 23
}
if template_exists; then exit 1; fi

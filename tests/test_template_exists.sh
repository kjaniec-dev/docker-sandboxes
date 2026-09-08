#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/sbx" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "template ls --json" && "${MOCK_JSON:-0}" == 1 ]]; then
  printf '%s\n' '{"images":[{"id":"abc","repository":"docker.io/library/claude-sbx","tag":"local","flavor":"claude-code-docker"}]}'
elif [[ "$*" == "template ls" ]]; then
  printf '%s\n' 'docker.io/library/claude-sbx local 753b231c8eaa claude-code-docker 2 days ago'
  for _ in $(seq 1 100000); do
    printf '%s\n' 'other-template'
  done
fi
MOCK
chmod +x "$tmp/bin/sbx"

PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/bin/claude-sbx'; template_exists"
MOCK_JSON=1 PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/bin/claude-sbx'; template_exists"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/mkdir" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "mkdir invoked while sourcing" >&2
exit 99
MOCK
chmod +x "$tmp/bin/mkdir"

PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/codex/scripts/verify.sh'"
PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/bin/codex-sbx-rebuild'"
PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/claude-code/scripts/verify.sh'"
PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/bin/claude-sbx-rebuild'"
PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/antigravity-cli/scripts/verify.sh'"
PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh'"
PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/bin/agy-sbx-rebuild'"

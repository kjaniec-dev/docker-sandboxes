#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_LOG"
if [[ "$*" == "plugin marketplace update claude-plugins-official" && ! -e "$MOCK_STATE" ]]; then
  touch "$MOCK_STATE"
  exit 1
fi
MOCK
chmod +x "$tmp/bin/claude"

export MOCK_LOG="$tmp/commands.log"
export MOCK_STATE="$tmp/marketplace-added"
PATH="$tmp/bin:$PATH" bash -c "source '$ROOT/harnesses/claude-code/scripts/bootstrap.sh'; refresh_official_marketplace"
grep -Fxq 'plugin marketplace add anthropics/claude-plugins-official' "$MOCK_LOG"
grep -Fxq 'plugin marketplace update claude-plugins-official' "$MOCK_LOG"

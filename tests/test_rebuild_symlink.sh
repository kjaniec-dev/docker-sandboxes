#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_LOG"
MOCK
cat >"$tmp/bin/sbx" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'sbx %s\n' "$*" >>"$MOCK_LOG"
MOCK
chmod +x "$tmp/bin/docker" "$tmp/bin/sbx"

ln -s "$ROOT/bin/claude-sbx-rebuild" "$tmp/rebuild"
export MOCK_LOG="$tmp/commands.log"
export PATH="$tmp/bin:$PATH"
"$tmp/rebuild"

grep -Fq "docker build --pull -t claude-sbx:local -f $ROOT/harnesses/claude-code/Dockerfile $ROOT" "$MOCK_LOG"
grep -Fq "docker image save claude-sbx:local -o $ROOT/.build/claude-sbx.tar" "$MOCK_LOG"

ln -s "$ROOT/bin/codex-sbx-rebuild" "$tmp/rebuild-codex"
"$tmp/rebuild-codex"

grep -Fq "docker build --pull -t codex-sbx:local -f $ROOT/harnesses/codex/Dockerfile $ROOT" "$MOCK_LOG"
grep -Fq "docker image save codex-sbx:local -o $ROOT/.build/codex-sbx.tar" "$MOCK_LOG"

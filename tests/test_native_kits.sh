#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Optional native contract test: host can supply the actual minimum CLI.
if [[ -z "${SBX_TEST_CLI:-}" ]]; then
  echo 'test_native_kits.sh: SKIP (set SBX_TEST_CLI to sbx 0.42.1+)'
  exit 0
fi
for harness in claude-code codex opencode antigravity-cli junie; do
  kit="$ROOT/harnesses/$harness/kit"
  "$SBX_TEST_CLI" kit validate "$kit" --kit-arg 'harness_root=/tmp/harness with "quotes"' \
    --kit-arg 'skills_root=/tmp/shared skills' --json | jq -e '.valid == true and .warnings == []' >/dev/null
  manifest="$("$SBX_TEST_CLI" kit inspect "$kit" --kit-arg 'harness_root=/tmp/harness with "quotes"' \
    --kit-arg 'skills_root=/tmp/shared skills' --json)"
  jq -e --arg harness "$harness" '
    .kind == "sandbox" and
    .environment.variables.HARNESS_ROOT == "/tmp/harness with \"quotes\"" and
    .environment.variables.SHARED_SKILLS_ROOT == "/tmp/shared skills" and
    .setup.install[0].user == "1000" and
    .setup.install[0].command == ("bash \"$HARNESS_ROOT/harnesses/" + $harness + "/scripts/bootstrap.sh\"") and
    (if $harness == "junie" then
      .sandbox.entrypoint == ["/tmp/harness with \"quotes\"/harnesses/junie/scripts/run.sh"]
    elif $harness == "antigravity-cli" then .sandbox.entrypoint == ["agy"]
    else .extends == (if $harness == "claude-code" then "claude" else $harness end) end)
  ' <<<"$manifest" >/dev/null
done
echo 'test_native_kits.sh: PASS'

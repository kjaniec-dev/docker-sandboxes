#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for harness in claude-code codex opencode antigravity-cli junie; do
  spec="$ROOT/harnesses/$harness/kit/spec.yaml"
  if grep -Eq 'skills_root|SHARED_SKILLS_ROOT' "$spec"; then
    echo "obsolete manual skills contract in $spec" >&2
    exit 1
  fi
  if ! grep -Eq '^[[:space:]]+- docs\.docker\.com$' "$spec"; then
    echo "missing Docker Docs network allowlist entry in $spec" >&2
    exit 1
  fi
done

# Optional native contract test: host can supply the actual minimum CLI.
if [[ -z "${SBX_TEST_CLI:-}" ]]; then
  echo 'test_native_kits.sh: SKIP (set SBX_TEST_CLI to sbx 0.43.0+)'
  exit 0
fi
for harness in claude-code codex opencode antigravity-cli junie; do
  kit="$ROOT/harnesses/$harness/kit"
  kit_args=()
  if [[ "$harness" != claude-code ]]; then
    kit_args=(--kit-arg 'harness_root=/tmp/harness with "quotes"')
  fi
  "$SBX_TEST_CLI" kit validate "$kit" "${kit_args[@]}" --json |
    jq -e '.valid == true and .warnings == []' >/dev/null
  manifest="$("$SBX_TEST_CLI" kit inspect "$kit" "${kit_args[@]}" --json)"
  jq -e --arg harness "$harness" '
    .kind == "sandbox" and
    .environment.variables.SHARED_SKILLS_ROOT == null and
    (if $harness == "claude-code" then
      .environment.variables.HARNESS_ROOT == null and
      .setup.install[0].user == "1000" and
      .setup.install[0].command == "bash /usr/local/lib/claude-sbx/bootstrap.sh" and
      .sandbox.image == "claude-sbx:local" and
      .extends == "claude"
    elif $harness == "codex" then
      .environment.variables.HARNESS_ROOT == "/tmp/harness with \"quotes\"" and
      .setup.install[0].user == "1000" and
      .setup.install[0].command == "bash \"$HARNESS_ROOT/harnesses/codex/scripts/bootstrap.sh\"" and
      .sandbox.image == "codex-sbx:local" and
      .extends == "codex"
    elif $harness == "opencode" then
      .environment.variables.HARNESS_ROOT == "/tmp/harness with \"quotes\"" and
      .setup.install[0].user == "1000" and
      .setup.install[0].command == "bash \"$HARNESS_ROOT/harnesses/opencode/scripts/bootstrap.sh\"" and
      .sandbox.image == "opencode-sbx:local" and
      .extends == "opencode"
    elif $harness == "junie" then
      .environment.variables.HARNESS_ROOT == "/tmp/harness with \"quotes\"" and
      .setup.install[0].user == "1000" and
      .setup.install[0].command == "bash \"$HARNESS_ROOT/harnesses/junie/scripts/bootstrap.sh\"" and
      .sandbox.entrypoint == ["/tmp/harness with \"quotes\"/harnesses/junie/scripts/run.sh"]
    elif $harness == "antigravity-cli" then
      .environment.variables.HARNESS_ROOT == "/tmp/harness with \"quotes\"" and
      .setup.install[0].user == "1000" and
      .setup.install[0].command == "bash \"$HARNESS_ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh\"" and
      .sandbox.entrypoint == ["agy"]
    else
      .environment.variables.HARNESS_ROOT == "/tmp/harness with \"quotes\"" and
      .setup.install[0].user == "1000" and
      .setup.install[0].command == "bash \"$HARNESS_ROOT/harnesses/antigravity-cli/scripts/bootstrap.sh\""
    end)
  ' <<<"$manifest" >/dev/null
done
echo 'test_native_kits.sh: PASS'

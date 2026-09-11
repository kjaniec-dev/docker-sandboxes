#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

allow_block() {
  awk '/^    allow:/{f=1;next} f && /^ *- /{sub(/^ *- /,"");print;next} f{exit}' "$1"
}

new_harness() {
  SBX_NEW_HARNESS_ROOT="$1" "$ROOT/bin/sbx-new-harness" "${@:2}"
}

# Default shell-base generation into a temporary root.
target="$tmp/root1"
mkdir -p "$target"
out="$(new_harness "$target" demo)"

for path in \
  "$target/harnesses/demo/Dockerfile" \
  "$target/harnesses/demo/kit/spec.yaml"; do
  [[ -f "$path" ]] || {
    echo "missing: $path" >&2
    exit 1
  }
done
for path in \
  "$target/harnesses/demo/bin/demo-sbx" \
  "$target/harnesses/demo/scripts/bootstrap.sh" \
  "$target/harnesses/demo/scripts/verify.sh" \
  "$target/bin/demo-sbx" \
  "$target/bin/demo-sbx-rebuild" \
  "$target/tests/test_demo_layout.sh"; do
  [[ -x "$path" ]] || {
    echo "missing executable: $path" >&2
    exit 1
  }
done

grep -Fq 'FROM docker/sandbox-templates:shell-docker' "$target/harnesses/demo/Dockerfile"
grep -Fq 'NODE_VERSION=24.19.0' "$target/harnesses/demo/Dockerfile"
grep -Fq 'GO_VERSION=1.26.6' "$target/harnesses/demo/Dockerfile"
grep -Fq 'install-system-toolchain.sh' "$target/harnesses/demo/Dockerfile"
grep -Fq 'install-user-toolchain.sh' "$target/harnesses/demo/Dockerfile"

grep -Fq 'name: demo-sbx' "$target/harnesses/demo/kit/spec.yaml"
grep -Fq 'image: demo-sbx:local' "$target/harnesses/demo/kit/spec.yaml"
grep -Fq 'harnesses/demo/scripts/bootstrap.sh' "$target/harnesses/demo/kit/spec.yaml"
grep -Fq 'kit.args.harness_root' "$target/harnesses/demo/kit/spec.yaml"
grep -Fq 'extends:' "$target/harnesses/demo/kit/spec.yaml" && {
  echo 'unexpected extends in shell-base kit' >&2
  exit 1
}
# The tooling allowlist must match the canonical shared list.
diff <(allow_block "$target/harnesses/demo/kit/spec.yaml") \
  <(allow_block "$ROOT/harnesses/claude-code/kit/spec.yaml") >/dev/null

grep -Fq 'TEMPLATE="demo-sbx:local"' "$target/harnesses/demo/bin/demo-sbx"
grep -Fq 'SANDBOX_PREFIX="demo"' "$target/harnesses/demo/bin/demo-sbx"
grep -Fq 'shared/launcher.sh' "$target/harnesses/demo/bin/demo-sbx"
grep -Fq 'harnesses/demo/bin/demo-sbx' "$target/bin/demo-sbx"
grep -Fq 'shared/rebuild.sh' "$target/bin/demo-sbx-rebuild"
grep -Fq 'harnesses/demo/Dockerfile' "$target/bin/demo-sbx-rebuild"
grep -Fq 'verify-toolchain.sh' "$target/harnesses/demo/scripts/verify.sh"
grep -Fq 'skills.sh' "$target/harnesses/demo/scripts/bootstrap.sh"

# Generated shell sources parse, and the generated layout test passes.
while IFS= read -r -d '' file; do
  bash -n "$file" || {
    echo "syntax error in $file" >&2
    exit 1
  }
done < <(find "$target" -type f \( -name '*.sh' -o -path '*/bin/*' \) -print0)
bash "$target/tests/test_demo_layout.sh" >/dev/null

# Printed next steps mention the manual wiring.
grep -Fq 'Makefile' <<<"$out"
grep -Fq 'README' <<<"$out"
grep -Fq 'AGENTS.md' <<<"$out"
grep -Fq 'docs/usage.md' <<<"$out"
grep -Fq 'demo-sbx-rebuild' <<<"$out"

# Custom prefix and native base.
new_harness "$target" demo2 --prefix dem --base codex >/dev/null
grep -Fq 'FROM docker/sandbox-templates:codex-docker' "$target/harnesses/demo2/Dockerfile"
grep -Fq 'extends: codex' "$target/harnesses/demo2/kit/spec.yaml"
grep -Fq 'image: dem-sbx:local' "$target/harnesses/demo2/kit/spec.yaml" && {
  echo 'unexpected sandbox image in native-base kit' >&2
  exit 1
}
grep -Fq 'SANDBOX_PREFIX="dem"' "$target/harnesses/demo2/bin/dem-sbx"
grep -Fq 'TEMPLATE="dem-sbx:local"' "$target/harnesses/demo2/bin/dem-sbx"
[[ -x "$target/bin/dem-sbx" && -x "$target/bin/dem-sbx-rebuild" ]]
[[ -x "$target/tests/test_dem_layout.sh" ]]
bash "$target/tests/test_dem_layout.sh" >/dev/null

# Claude base uses CLAUDE.md instructions and extends claude.
new_harness "$target" demo3 --base claude-code >/dev/null
grep -Fq 'extends: claude' "$target/harnesses/demo3/kit/spec.yaml"
grep -Fq 'filename: CLAUDE.md' "$target/harnesses/demo3/kit/spec.yaml"

# Existing harness or delegate collision fails without touching the tree.
status=0
new_harness "$target" demo >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]
status=0
new_harness "$target" fresh --prefix demo >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]
[[ ! -e "$target/harnesses/fresh" ]]

# Invalid inputs fail.
status=0
new_harness "$target" Demo >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]
status=0
new_harness "$target" 'de mo' >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]
status=0
new_harness "$target" >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]
status=0
new_harness "$target" ok1 --base windows >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]
status=0
new_harness "$target" ok2 --prefix Bad >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]

echo 'test_new_harness.sh: PASS'

#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

check_java_major() {
  local label="$1"
  local version="$2"
  local line
  local major="unknown"
  while IFS= read -r line; do
    if [[ "$label" == 'Java' && "$line" =~ ^openjdk[[:space:]]([0-9]+)([.[:space:]]|$) ]]; then
      major="${BASH_REMATCH[1]}"
      break
    fi
    if [[ "$label" == 'javac' && "$line" =~ ^javac[[:space:]]([0-9]+)([.[:space:]]|$) ]]; then
      major="${BASH_REMATCH[1]}"
      break
    fi
  done <<<"$version"
  # Require Java 25.
  [[ "$major" == "25" ]] || {
    echo "unexpected $label version: $version (expected major 25; observed major $major)" >&2
    exit 1
  }
}

required_commands=(codex git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv serena go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle)
for cmd in "${required_commands[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "missing command: $cmd" >&2
    exit 1
  }
done
skills_dir="$HOME/.agents/skills"
[[ -f "$skills_dir/using-superpowers/SKILL.md" ]] || {
  echo "missing Codex skill: superpowers" >&2
  exit 1
}
[[ -f "$skills_dir/brainstorming/SKILL.md" ]] || {
  echo "missing Codex skill: brainstorming" >&2
  exit 1
}
[[ -f "$skills_dir/caveman/SKILL.md" ]] || {
  echo "missing Codex skill: caveman" >&2
  exit 1
}
[[ -f "$skills_dir/playwright-cli/SKILL.md" ]] || {
  echo "missing Codex skill: playwright-cli" >&2
  exit 1
}
java_version="$(java --version 2>&1)"
check_java_major 'Java' "$java_version"
javac_version="$(javac --version 2>&1)"
check_java_major 'javac' "$javac_version"
mvn --version >/dev/null
gradle --version >/dev/null
[[ "$(node --version)" == "v24.19.0" ]] || {
  echo "unexpected Node version: $(node --version)" >&2
  exit 1
}
grep -Fq 'go1.26.6' <<<"$(go version)" || {
  echo "unexpected Go version: $(go version)" >&2
  exit 1
}
docker compose version >/dev/null
echo "codex-sbx verification passed"

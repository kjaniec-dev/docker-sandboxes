#!/usr/bin/env bash
# Shared sandbox toolchain checks. Sourcing only defines functions.

verify_toolchain_commands() {
  local prefix="$1"
  local agent="$2"
  shift 2
  local cmd
  # Extra harness commands retain their position between uv and Go tooling.
  local required_commands=("$agent" git gh curl wget ssh rg fd jq yq fzf make just shellcheck shfmt docker node npm corepack pnpm python3 uv "$@" go gopls goimports golangci-lint staticcheck govulncheck dlv playwright-cli psql sqlite3 redis-cli java javac mvn gradle)
  for cmd in "${required_commands[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "missing ${prefix}command: $cmd" >&2
      exit 1
    }
  done
}

check_java_major() {
  local prefix="$1"
  local label="$2"
  local version="$3"
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
    echo "unexpected ${prefix}$label version: $version (expected major 25; observed major $major)" >&2
    exit 1
  }
}

# Preserve raw stderr/status by default, or the harness's named failure message.
verify_toolchain_tool() {
  local prefix="$1" errors="$2" label="$3"
  shift 3
  if [[ "$errors" == named ]]; then
    if ! "$@" >/dev/null 2>&1; then
      echo "${prefix}$label verification failed: $*" >&2
      exit 1
    fi
  else
    "$@" >/dev/null
  fi
}

verify_toolchain() {
  local prefix="${1:-}" errors="${2:-raw}"
  local java_version javac_version
  java_version="$(java --version 2>&1)"
  check_java_major "$prefix" 'Java' "$java_version"
  javac_version="$(javac --version 2>&1)"
  check_java_major "$prefix" 'javac' "$javac_version"
  verify_toolchain_tool "$prefix" "$errors" Maven mvn --version
  verify_toolchain_tool "$prefix" "$errors" Gradle gradle --version
  [[ "$(node --version)" == "v24.19.0" ]] || {
    echo "unexpected ${prefix}Node version: $(node --version)" >&2
    exit 1
  }
  grep -Fq 'go1.26.6' <<<"$(go version)" || {
    echo "unexpected ${prefix}Go version: $(go version)" >&2
    exit 1
  }
  verify_toolchain_tool "$prefix" "$errors" 'Docker Compose' docker compose version
}

#!/usr/bin/env bash
set -euo pipefail

main() {
  # Junie bundles a JVM whose cacerts does not include the sandbox proxy CA.
  # Use the system Java trust store, populated by Docker Sandboxes at runtime.
  local trust_store=/etc/ssl/certs/java/cacerts
  if [[ ! -r "$trust_store" ]]; then
    printf 'Junie: system Java trust store is missing or unreadable: %s\n' "$trust_store" >&2
    return 1
  fi
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }-Djavax.net.ssl.trustStore=$trust_store"

  if [[ -n "${JUNIE_API_KEY:-}" ]]; then
    exec junie --auth="$JUNIE_API_KEY" "$@"
  fi
  exec junie "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

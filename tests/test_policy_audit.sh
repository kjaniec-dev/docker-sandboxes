#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/sbx" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_LOG"
case "$1" in
  ls)
    [[ "${2:-}" == --json ]]
    cat <<'JSON'
{"sandboxes":[{"name":"codex-repo-11111111"},{"name":"junie-repo-22222222"},{"name":"plain-33333333"},{"name":"broken-44444444"}]}
JSON
    ;;
  policy)
    [[ "${2:-}" == log ]]
    name="$3"
    case "$name" in
      codex-repo-11111111)
        cat <<'LOG'
Blocked requests:
SANDBOX      TYPE     HOST                   PROXY        RULE            REASON         LAST SEEN        COUNT
codex-repo-11111111   network  blocked.example.com    transparent  domain-blocked  default-deny   10:15:25 29-Jan  3
codex-repo-11111111   network  api.openai.com         transparent  domain-blocked  default-deny   10:16:25 29-Jan  1

Allowed requests:
SANDBOX      TYPE     HOST                   PROXY          RULE             REASON   LAST SEEN        COUNT
codex-repo-11111111   network  github.com      forward        domain-allowed            10:15:23 29-Jan  42
LOG
        ;;
      junie-repo-22222222)
        cat <<'LOG'
Blocked requests:
SANDBOX      TYPE     HOST                   PROXY        RULE            REASON         LAST SEEN        COUNT
junie-repo-22222222   network  oraios-software.de               transparent  domain-blocked  default-deny   11:15:25 29-Jan  2
junie-repo-22222222   network  ingrazzio-cloud-prod.labs.jb.gg  transparent  domain-blocked  default-deny   11:16:25 29-Jan  5

Allowed requests:
SANDBOX      TYPE     HOST                   PROXY          RULE             REASON   LAST SEEN        COUNT
LOG
        ;;
      plain-33333333)
        cat <<'LOG'
Blocked requests:
SANDBOX      TYPE     HOST                   PROXY        RULE            REASON         LAST SEEN        COUNT
plain-33333333   network  weird.example        transparent  domain-blocked  default-deny   12:15:25 29-Jan  7

Allowed requests:
SANDBOX      TYPE     HOST                   PROXY          RULE             REASON   LAST SEEN        COUNT
LOG
        ;;
      broken-44444444)
        echo "boom" >&2
        exit 9
        ;;
      *) echo "Unexpected policy log sandbox: $name" >&2; exit 92 ;;
    esac
    ;;
  *) echo "Unexpected sbx operation: $*" >&2; exit 92 ;;
esac
MOCK
chmod +x "$tmp/bin/sbx"
export PATH="$tmp/bin:$PATH"
export MOCK_LOG="$tmp/commands.log"
: >"$MOCK_LOG"

out="$("$ROOT/bin/sbx-policy-audit")"

# Blocked domains missing from the kit get a scoped allow command and kit pointer.
grep -Fq 'sbx policy allow network --sandbox codex-repo-11111111 blocked.example.com' <<<"$out"
grep -Fq 'harnesses/codex/kit/spec.yaml' <<<"$out"
grep -Fq 'sbx policy allow network --sandbox junie-repo-22222222 oraios-software.de' <<<"$out"
grep -Fq 'harnesses/junie/kit/spec.yaml' <<<"$out"

# Domains already allowed by the kit must not produce an allow command;
# the report suggests recreation instead.
grep -Fq 'blocked.example.com (3)' <<<"$out"
grep -Fq 'api.openai.com (1)' <<<"$out"
grep -F 'allow network --sandbox codex-repo-11111111 api.openai.com' <<<"$out" && {
  echo 'unexpected match' >&2
  exit 1
}
grep -F 'allow network --sandbox junie-repo-22222222 ingrazzio-cloud-prod.labs.jb.gg' <<<"$out" && {
  echo 'unexpected match' >&2
  exit 1
}
grep -iq 'recreate' <<<"$out"

# Sandboxes without a matching harness prefix are still reported.
grep -Fq 'sbx policy allow network --sandbox plain-33333333 weird.example' <<<"$out"
grep -Fq 'kit: unknown' <<<"$out"

# A failing policy log warns but does not abort the remaining sandboxes.
grep -Fq 'broken-44444444' <<<"$out"
grep -Fq 'warning' <<<"$out"

# Default invocation lists sandboxes and queries each log with default flags.
grep -Fq 'ls --json' "$MOCK_LOG"
grep -Fq 'policy log codex-repo-11111111 --type network --limit 1000' "$MOCK_LOG"

# Single-name mode audits only that sandbox and passes --limit through.
: >"$MOCK_LOG"
out="$("$ROOT/bin/sbx-policy-audit" junie-repo-22222222 --limit 50)"
grep -Fq 'oraios-software.de' <<<"$out"
grep -F 'codex-repo-11111111' <<<"$out" && {
  echo 'unexpected match' >&2
  exit 1
}
grep -F 'ls --json' "$MOCK_LOG" && {
  echo 'unexpected ls' >&2
  exit 1
}
grep -Fq 'policy log junie-repo-22222222 --type network --limit 50' "$MOCK_LOG"

# Unknown options are rejected.
status=0
"$ROOT/bin/sbx-policy-audit" --bogus >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]

# Missing sbx fails cleanly.
status=0
env PATH="/usr/bin:/bin" "$ROOT/bin/sbx-policy-audit" >/dev/null 2>&1 || status=$?
[[ "$status" != 0 ]]

echo 'test_policy_audit.sh: PASS'

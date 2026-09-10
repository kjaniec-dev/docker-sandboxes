#!/usr/bin/env bash
set -euo pipefail

check_agy_mcp_managed_entries() {
  local config_file="$1"
  local conflicts

  if ! conflicts="$(jq -r '
    def check_entry($servers; $name; $expected):
      if ($servers | has($name)) then
        [$expected | to_entries[] | $servers[$name][.key] == .value] | all
      else
        true
      end;

    (.mcpServers // {}) as $servers |
    (if check_entry($servers; "serena"; {
      "command": "serena",
      "args": ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"],
      "disabled": false
    }) then empty else "serena" end),
    (if check_entry($servers; "context7"; {
      "serverUrl": "https://mcp.context7.com/mcp",
      "disabled": false
    }) then empty else "context7" end)
  ' "$config_file" 2>/dev/null)"; then
    printf 'Antigravity bootstrap: invalid JSON in %s\n' "$config_file" >&2
    return 1
  fi

  if [[ -n "$conflicts" ]]; then
    local name
    while IFS= read -r name; do
      printf "Antigravity bootstrap: conflicting managed MCP entry '%s' in %s\n" "$name" "$config_file" >&2
    done <<<"$conflicts"
    return 1
  fi
}

ensure_agy_mcp_config() {
  local config_file="$1"
  local config_dir
  local temporary_file

  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"

  if [[ -e "$config_file" ]] && ! jq empty "$config_file" >/dev/null 2>&1; then
    printf 'Antigravity bootstrap: invalid JSON in %s\n' "$config_file" >&2
    return 1
  fi

  if [[ -e "$config_file" ]] && ! check_agy_mcp_managed_entries "$config_file"; then
    return 1
  fi

  temporary_file="$(mktemp "$config_dir/.mcp_config.json.XXXXXX")"
  if [[ -e "$config_file" ]]; then
    if ! jq '
      .mcpServers = ((.mcpServers // {}) + {
        "serena": {
          "command": "serena",
          "args": ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"],
          "disabled": false
        },
        "context7": {
          "serverUrl": "https://mcp.context7.com/mcp",
          "disabled": false
        }
      })
    ' "$config_file" >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'Antigravity bootstrap: failed to update %s\n' "$config_file" >&2
      return 1
    fi
  else
    if ! jq -n '
      {
        "mcpServers": {
          "serena": {
            "command": "serena",
            "args": ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"],
            "disabled": false
          },
          "context7": {
            "serverUrl": "https://mcp.context7.com/mcp",
            "disabled": false
          }
        }
      }
    ' >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'Antigravity bootstrap: failed to create %s\n' "$config_file" >&2
      return 1
    fi
  fi

  mv -f "$temporary_file" "$config_file"
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

if [[ -z "${HARNESS_ROOT:-}" ]]; then
  HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi
# shellcheck source=/dev/null
source "$HARNESS_ROOT/shared/skills.sh"

link_shared_skills "$HOME/.gemini/config/skills"

ensure_agy_mcp_config "$HOME/.gemini/config/mcp_config.json"

printf '%s\n' 'Antigravity bootstrap setup complete.'

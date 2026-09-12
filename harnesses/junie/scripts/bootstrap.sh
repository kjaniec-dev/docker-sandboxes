#!/usr/bin/env bash
set -euo pipefail

check_junie_mcp_managed_entries() {
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
      "args": ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"]
    }) then empty else "serena" end),
    (if check_entry($servers; "context7"; {
      "url": "https://mcp.context7.com/mcp"
    }) then empty else "context7" end)
  ' "$config_file" 2>/dev/null)"; then
    printf 'Junie bootstrap: invalid JSON in %s\n' "$config_file" >&2
    return 1
  fi

  if [[ -n "$conflicts" ]]; then
    local name
    while IFS= read -r name; do
      printf "Junie bootstrap: conflicting managed MCP entry '%s' in %s\n" "$name" "$config_file" >&2
    done <<<"$conflicts"
    return 1
  fi
}

ensure_junie_config() {
  local config_file="$1"
  local config_dir
  local temporary_file

  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"

  if [[ -e "$config_file" ]] && ! jq empty "$config_file" >/dev/null 2>&1; then
    printf 'Junie bootstrap: invalid JSON in %s\n' "$config_file" >&2
    return 1
  fi

  temporary_file="$(mktemp "$config_dir/.config.json.XXXXXX")"
  if [[ -e "$config_file" ]]; then
    if ! jq '. + {"brave": true}' "$config_file" >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'Junie bootstrap: failed to update %s\n' "$config_file" >&2
      return 1
    fi
  else
    if ! jq -n '{"brave": true}' >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'Junie bootstrap: failed to create %s\n' "$config_file" >&2
      return 1
    fi
  fi

  mv -f "$temporary_file" "$config_file"
}

ensure_junie_mcp_config() {
  local config_file="$1"
  local config_dir
  local temporary_file

  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"

  if [[ -e "$config_file" ]] && ! jq empty "$config_file" >/dev/null 2>&1; then
    printf 'Junie bootstrap: invalid JSON in %s\n' "$config_file" >&2
    return 1
  fi

  if [[ -e "$config_file" ]] && ! check_junie_mcp_managed_entries "$config_file"; then
    return 1
  fi

  temporary_file="$(mktemp "$config_dir/.mcp.json.XXXXXX")"
  if [[ -e "$config_file" ]]; then
    if ! jq '
      .mcpServers = ((.mcpServers // {}) + {
        "serena": ((.mcpServers.serena // {}) + {
          "command": "serena",
          "args": ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"]
        }),
        "context7": ((.mcpServers.context7 // {}) + {
          "url": "https://mcp.context7.com/mcp"
        })
      })
    ' "$config_file" >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'Junie bootstrap: failed to update %s\n' "$config_file" >&2
      return 1
    fi
  else
    if ! jq -n '
      {
        "mcpServers": {
          "serena": {
            "command": "serena",
            "args": ["start-mcp-server", "--context=ide-assistant", "--project-from-cwd"]
          },
          "context7": {
            "url": "https://mcp.context7.com/mcp"
          }
        }
      }
    ' >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'Junie bootstrap: failed to create %s\n' "$config_file" >&2
      return 1
    fi
  fi

  mv -f "$temporary_file" "$config_file"
}

install_junie() {
  export PATH="$HOME/.junie/bin:$HOME/.local/bin:$PATH"
  if ! command -v junie >/dev/null 2>&1; then
    curl -fsSL https://junie.jetbrains.com/install.sh | bash
  fi
  command -v junie >/dev/null 2>&1 || {
    echo 'Junie bootstrap: installer did not provide junie on PATH' >&2
    return 1
  }
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

install_junie

if [[ -z "${HARNESS_ROOT:-}" ]]; then
  HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi
# shellcheck source=/dev/null
source "$HARNESS_ROOT/shared/skills.sh"

link_shared_skills "$HOME/.junie/skills"

ensure_junie_config "$HOME/.junie/config.json"
ensure_junie_mcp_config "$HOME/.junie/mcp/mcp.json"

printf '%s\n' 'Junie bootstrap setup complete.'

#!/usr/bin/env bash
set -euo pipefail

CAVEMAN_TAG="v2.2.0"
CAVEMAN_REVISION="9aa63945a349bef17206540650db48c30fafbdf2"

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

ensure_git_checkout() {
  if [[ $# -lt 2 || $# -gt 3 ]]; then
    printf 'Junie bootstrap: usage: ensure_git_checkout <directory> <url> [<ref>]\n' >&2
    return 2
  fi

  local directory="$1"
  local url="$2"
  local ref="${3:-}"

  if [[ -e "$directory/.git" ]]; then
    if [[ -z "$ref" ]]; then
      git -C "$directory" pull --ff-only
    fi
  elif [[ ! -e "$directory" ]]; then
    if [[ -n "$ref" ]]; then
      git clone --depth=1 --branch "$ref" "$url" "$directory"
    else
      git clone --depth=1 "$url" "$directory"
    fi
  else
    printf 'Junie bootstrap: refusing to replace non-git %s\n' "$directory" >&2
    return 1
  fi
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

superpowers_dir="$HOME/.junie/superpowers"
ensure_git_checkout \
  "$superpowers_dir" \
  https://github.com/obra/superpowers.git

caveman_dir="$HOME/.junie/caveman"
ensure_git_checkout \
  "$caveman_dir" \
  https://github.com/JuliusBrussee/caveman.git \
  "$CAVEMAN_TAG"
if [[ "$(git -C "$caveman_dir" rev-parse HEAD)" != "$CAVEMAN_REVISION" ]]; then
  printf 'Junie bootstrap: unexpected Caveman revision in %s\n' "$caveman_dir" >&2
  exit 1
fi

skills_dir="$HOME/.junie/skills"
mkdir -p "$skills_dir"
for skill_path in "$superpowers_dir"/skills/*/; do
  skill_path="${skill_path%/}"
  [[ -d "$skill_path" ]] || continue
  ln -sfn "$skill_path" "$skills_dir/$(basename "$skill_path")"
done
ln -sfn "$caveman_dir/skills/caveman" "$skills_dir/caveman"

playwright-cli install --skills agents --global
ln -sfn "$HOME/.agents/skills/playwright-cli" "$skills_dir/playwright-cli"

ensure_junie_mcp_config "$HOME/.junie/mcp/mcp.json"

mkdir -p "$HOME/.cache/claude-sbx"
touch "$HOME/.cache/claude-sbx/junie-bootstrap-v1"

printf '%s\n' 'Junie bootstrap setup complete.'

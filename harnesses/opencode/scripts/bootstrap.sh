#!/usr/bin/env bash
set -euo pipefail

CAVEMAN_TAG="v2.2.0"
CAVEMAN_REVISION="9aa63945a349bef17206540650db48c30fafbdf2"

check_jsonc_managed_entries() {
  local config_file="$1"

  node - "$config_file" <<'NODE'
const fs = require('fs');

const file = process.argv[2];
const source = fs.readFileSync(file, 'utf8');
let output = '';
let inString = false;
let escaped = false;
let lineComment = false;
let blockComment = false;

for (let index = 0; index < source.length; index += 1) {
  const character = source[index];
  const next = source[index + 1];

  if (lineComment) {
    if (character === '\n') {
      lineComment = false;
      output += character;
    }
    continue;
  }
  if (blockComment) {
    if (character === '*' && next === '/') {
      blockComment = false;
      index += 1;
    } else if (character === '\n') {
      output += character;
    }
    continue;
  }
  if (inString) {
    output += character;
    if (escaped) {
      escaped = false;
    } else if (character === '\\') {
      escaped = true;
    } else if (character === '"') {
      inString = false;
    }
    continue;
  }
  if (character === '"') {
    inString = true;
    output += character;
  } else if (character === '/' && next === '/') {
    lineComment = true;
    index += 1;
  } else if (character === '/' && next === '*') {
    blockComment = true;
    index += 1;
  } else {
    output += character;
  }
}

try {
  const config = JSON.parse(output.replace(/,\s*([}\]])/g, '$1'));
  const mcp = config && typeof config.mcp === 'object' && !Array.isArray(config.mcp)
    ? config.mcp
    : {};
  const expected = {
    serena: {
      type: 'local',
      command: ['serena', 'start-mcp-server', '--context=ide-assistant', '--project-from-cwd'],
      enabled: true,
    },
    context7: {
      type: 'remote',
      url: 'https://mcp.context7.com/mcp',
      enabled: true,
    },
  };

  for (const name of Object.keys(expected)) {
    if (!Object.prototype.hasOwnProperty.call(mcp, name)) continue;
    const actual = mcp[name];
    const managed = expected[name];
    const matches = Object.keys(managed).every((key) =>
      JSON.stringify(actual && actual[key]) === JSON.stringify(managed[key])
    );
    if (!matches) {
      console.error(`OpenCode bootstrap: conflicting managed MCP entry '${name}' in ${file}`);
      process.exit(1);
    }
  }
} catch (error) {
  console.error(`OpenCode bootstrap: invalid JSONC in ${file}`);
  process.exit(1);
}
NODE
}

ensure_opencode_config() {
  local config_file="$1"
  local config_dir
  local temporary_file

  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"

  if [[ -e "$config_dir/opencode.jsonc" ]] && ! check_jsonc_managed_entries "$config_dir/opencode.jsonc"; then
    return 1
  fi

  if [[ -e "$config_file" ]] && ! jq empty "$config_file" >/dev/null 2>&1; then
    printf 'OpenCode bootstrap: invalid JSON in %s\n' "$config_file" >&2
    return 1
  fi

  temporary_file="$(mktemp "$config_dir/.opencode.json.XXXXXX")"
  if [[ -e "$config_file" ]]; then
    if ! jq '
      . + {
        "$schema": "https://opencode.ai/config.json",
        "enabled_providers": ["opencode-go"],
        "mcp": ((.mcp // {}) + {
          "serena": {
            "type": "local",
            "command": ["serena", "start-mcp-server", "--context=ide-assistant", "--project-from-cwd"],
            "enabled": true
          },
          "context7": {
            "type": "remote",
            "url": "https://mcp.context7.com/mcp",
            "enabled": true
          }
        })
      }
    ' "$config_file" >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'OpenCode bootstrap: failed to update %s\n' "$config_file" >&2
      return 1
    fi
  else
    if ! jq -n '
      {
        "$schema": "https://opencode.ai/config.json",
        "enabled_providers": ["opencode-go"],
        "mcp": {
          "serena": {
            "type": "local",
            "command": ["serena", "start-mcp-server", "--context=ide-assistant", "--project-from-cwd"],
            "enabled": true
          },
          "context7": {
            "type": "remote",
            "url": "https://mcp.context7.com/mcp",
            "enabled": true
          }
        }
      }
    ' >"$temporary_file"; then
      rm -f "$temporary_file"
      printf 'OpenCode bootstrap: failed to create %s\n' "$config_file" >&2
      return 1
    fi
  fi

  mv -f "$temporary_file" "$config_file"
}

ensure_git_checkout() {
  if [[ $# -lt 2 || $# -gt 3 ]]; then
    printf 'OpenCode bootstrap: usage: ensure_git_checkout <directory> <url> [<ref>]\n' >&2
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
    printf 'OpenCode bootstrap: refusing to replace non-git %s\n' "$directory" >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

superpowers_dir="$HOME/.opencode/superpowers"
ensure_git_checkout \
  "$superpowers_dir" \
  https://github.com/obra/superpowers.git

caveman_dir="$HOME/.opencode/caveman"
ensure_git_checkout \
  "$caveman_dir" \
  https://github.com/JuliusBrussee/caveman.git \
  "$CAVEMAN_TAG"
if [[ "$(git -C "$caveman_dir" rev-parse HEAD)" != "$CAVEMAN_REVISION" ]]; then
  printf 'OpenCode bootstrap: unexpected Caveman revision in %s\n' "$caveman_dir" >&2
  exit 1
fi

mkdir -p "$HOME/.agents/skills"
ln -sfn "$superpowers_dir/skills" "$HOME/.agents/skills/superpowers"
ln -sfn "$caveman_dir/skills/caveman" "$HOME/.agents/skills/caveman"
playwright-cli install --skills agents --global

mkdir -p "$HOME/.config/opencode"
ensure_opencode_config "$HOME/.config/opencode/config.json"
mkdir -p "$HOME/.cache/claude-sbx"
touch "$HOME/.cache/claude-sbx/opencode-bootstrap-v1"

printf '%s\n' 'OpenCode bootstrap setup complete.'

#!/usr/bin/env bash
set -euo pipefail

# Sourced by harness launchers after their paths and agent identity are set.
DEFAULT_AGENT_ARGS=()
DEFAULT_AGENT_ARG_CONFLICTS=()

sandbox_name_for_repo() {
  local repo_root="$1"
  local base slug digest
  base="$(basename "$repo_root")"
  slug="$(printf '%s' "$base" | tr '[:upper:]_' '[:lower:]-' | sed -E 's/[^a-z0-9.+-]+/-/g; s/^-+//; s/-+$//')"
  digest="$(printf '%s' "$repo_root" | shasum -a 256 | awk '{print substr($1,1,8)}')"
  printf '%s-%s-%s\n' "$SANDBOX_PREFIX" "$slug" "$digest"
}

repo_root_from_cwd() {
  git rev-parse --show-toplevel
}

ensure_worktrees_ignored() {
  local repo_root="$1"
  local probe="$repo_root/.worktrees/.sbx-ignore-probe"
  mkdir -p "$repo_root/.worktrees"
  git -C "$repo_root" check-ignore -q "$probe"
}

append_harness_source_mounts() {
  local repo_root="$1"

  if [[ "$repo_root" == "$ROOT/.worktrees/"* ]]; then
    mounts+=("$ROOT/harnesses:ro" "$ROOT/shared:ro")
  elif [[ "$repo_root" != "$ROOT" ]]; then
    mounts+=("$ROOT:ro")
  fi
}

main() {
  command -v sbx >/dev/null 2>&1 || {
    echo "$SANDBOX_PREFIX-sbx: 'sbx' not found. Install Docker Sandboxes 0.43.0 or newer." >&2
    return 1
  }

  command -v jq >/dev/null 2>&1 || {
    echo "$SANDBOX_PREFIX-sbx: install jq on the host (brew install jq)." >&2
    return 1
  }

  local repo_root name sandboxes store
  local -a run_args mounts forwarded_args default_agent_args default_agent_arg_conflicts
  if ! repo_root="$(repo_root_from_cwd 2>/dev/null)"; then
    echo "$SANDBOX_PREFIX-sbx: run this command from inside a Git repository" >&2
    return 2
  fi

  if ! ensure_worktrees_ignored "$repo_root"; then
    printf '%s-sbx: .worktrees/ is not ignored by Git.\n\nAdd .worktrees/ to the repository .gitignore, then run %s-sbx again.\n' \
      "$SANDBOX_PREFIX" "$SANDBOX_PREFIX" >&2
    return 3
  fi

  name="$(sandbox_name_for_repo "$repo_root")"
  run_args=(run --name "$name")
  # shellcheck source=shared/skills.sh
  source "$ROOT/shared/skills.sh"
  store="$(shared_skills_store)" || return
  ensure_shared_skills "$store" || return
  mounts=("$repo_root")
  append_harness_source_mounts "$repo_root"
  # Reattachment must not pass workspaces again (sbx rejects them on reuse).
  sandboxes="$(sbx ls --json)" || return
  if ! jq -e --arg name "$name" 'any(.sandboxes[]; .name == $name)' <<<"$sandboxes" >/dev/null; then
    # Native create permits credential-binding prompts on the first launch.
    # Keep creation separate so Junie credentials remain session-only.
    sbx create --name "$name" --skills=readonly \
      --kit-arg "harness_root=$ROOT" \
      "$KIT" "${mounts[@]}" || return
  fi

  # Session-only, including an empty override to prevent a stale key from
  # taking precedence over JetBrains Account OAuth. Never persist it in YAML.
  if [[ "$SANDBOX_PREFIX" == junie ]]; then
    run_args+=(--env "JUNIE_API_KEY=${JUNIE_API_KEY:-}")
  fi

  forwarded_args=("$@")
  default_agent_args=()
  default_agent_arg_conflicts=()
  if declare -p DEFAULT_AGENT_ARGS >/dev/null 2>&1 && ((${#DEFAULT_AGENT_ARGS[@]} > 0)); then
    default_agent_args=("${DEFAULT_AGENT_ARGS[@]}")
  fi
  if declare -p DEFAULT_AGENT_ARG_CONFLICTS >/dev/null 2>&1 && ((${#DEFAULT_AGENT_ARG_CONFLICTS[@]} > 0)); then
    default_agent_arg_conflicts=("${DEFAULT_AGENT_ARG_CONFLICTS[@]}")
  fi

  local argument conflict use_defaults=true
  if ((${#forwarded_args[@]} > 0 && ${#default_agent_arg_conflicts[@]} > 0)); then
    for argument in "${forwarded_args[@]}"; do
      for conflict in "${default_agent_arg_conflicts[@]}"; do
        if [[ "$argument" == "$conflict" || "$argument" == "$conflict="* ]]; then
          use_defaults=false
          break 2
        fi
      done
    done
  fi
  if [[ "$use_defaults" == true && ${#default_agent_args[@]} -gt 0 ]]; then
    if ((${#forwarded_args[@]} > 0)); then
      forwarded_args=("${default_agent_args[@]}" "${forwarded_args[@]}")
    else
      forwarded_args=("${default_agent_args[@]}")
    fi
  fi

  if ((${#forwarded_args[@]} > 0)); then
    sbx "${run_args[@]}" -- "${forwarded_args[@]}"
  else
    sbx "${run_args[@]}" --
  fi
}

#!/usr/bin/env bash
set -euo pipefail

# Sourced by harness launchers after their paths and agent identity are set.
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

template_exists() {
  local repository="${TEMPLATE%:*}"
  local tag="${TEMPLATE##*:}"
  sbx template ls --json | jq -e --arg repository "$repository" --arg tag "$tag" \
    'any(.images[]; ((.repository | split("/") | last) == $repository and .tag == $tag))' >/dev/null
}

main() {
  command -v sbx >/dev/null 2>&1 || {
    echo "$SANDBOX_PREFIX-sbx: 'sbx' not found. Install Docker Sandboxes 0.42.1 or newer." >&2
    return 1
  }

  command -v jq >/dev/null 2>&1 || {
    echo "$SANDBOX_PREFIX-sbx: install jq on the host (brew install jq)." >&2
    return 1
  }

  local repo_root name store sandboxes
  local -a run_args mounts
  if ! repo_root="$(repo_root_from_cwd 2>/dev/null)"; then
    echo "$SANDBOX_PREFIX-sbx: run this command from inside a Git repository" >&2
    return 2
  fi

  if ! ensure_worktrees_ignored "$repo_root"; then
    printf '%s-sbx: .worktrees/ is not ignored by Git.\n\nAdd .worktrees/ to the repository .gitignore, then run %s-sbx again.\n' \
      "$SANDBOX_PREFIX" "$SANDBOX_PREFIX" >&2
    return 3
  fi

  if ! template_exists; then
    printf "%s-sbx: template '%s' is not loaded.\nRun:\n  %s/bin/%s-sbx-rebuild\n" \
      "$SANDBOX_PREFIX" "$TEMPLATE" "$ROOT" "$SANDBOX_PREFIX" >&2
    return 4
  fi

  name="$(sandbox_name_for_repo "$repo_root")"
  run_args=(run --name "$name")
  # shellcheck source=shared/skills.sh
  source "$ROOT/shared/skills.sh"
  store="$(shared_skills_store)" || return
  ensure_shared_skills "$store" || return
  mounts=("$repo_root")
  [[ "$repo_root" == "$ROOT" ]] || mounts+=("$ROOT:ro")
  mounts+=("$store")
  # Reattachment must not pass workspaces again (sbx rejects them on reuse).
  sandboxes="$(sbx ls --json)" || return
  if ! jq -e --arg name "$name" 'any(.sandboxes[]; .name == $name)' <<<"$sandboxes" >/dev/null; then
    # Native create permits credential-binding prompts on the first launch.
    # Keep creation separate so Junie credentials remain session-only.
    sbx create --name "$name" --template "$TEMPLATE" \
      --kit-arg "harness_root=$ROOT" --kit-arg "skills_root=$store" \
      "$KIT" "${mounts[@]}" || return
  fi

  # Session-only, including an empty override to prevent a stale key from
  # taking precedence over JetBrains Account OAuth. Never persist it in YAML.
  if [[ "$SANDBOX_PREFIX" == junie ]]; then
    run_args+=(--env "JUNIE_API_KEY=${JUNIE_API_KEY:-}")
  fi
  sbx "${run_args[@]}" -- "$@"
}

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

sandbox_exists() {
  # Consume the entire listing to avoid SIGPIPE with pipefail on large lists.
  sbx ls -q | grep -Fx "$1" >/dev/null
}

template_exists() {
  local repository="${TEMPLATE%:*}"
  local tag="${TEMPLATE##*:}"
  local listing

  # Docker Sandboxes 0.42.0+ provides a stable JSON shape. Keep a text-table
  # fallback for older CLIs and lightweight test stubs.
  if listing="$(sbx template ls --json 2>/dev/null)" && [[ -n "$listing" ]] &&
    jq -e --arg repository "$repository" --arg tag "$tag" \
      'any(.images[]?; ((.repository | split("/") | last) == $repository and .tag == $tag))' \
      <<<"$listing" >/dev/null 2>&1; then
    return 0
  fi

  sbx template ls | awk -v repository="$repository" -v tag="$tag" '
    { n = split($1, parts, "/") }
    parts[n] == repository && $2 == tag { found = 1 }
    END { exit !found }
  '
}

workspace_mounts() {
  local repo_root="$1"
  printf '%s\n' "$repo_root"
  if [[ "$repo_root" != "$ROOT" ]]; then
    printf '%s\n' "$ROOT:ro"
  fi
}

bootstrap_sandbox() {
  sbx exec "$1" bash "$BOOTSTRAP"
}

verify_sandbox() {
  sbx exec "$1" bash "$VERIFY"
}

main() {
  command -v sbx >/dev/null 2>&1 || {
    echo "$SANDBOX_PREFIX-sbx: 'sbx' not found. Install Docker Sandboxes 0.42.1 or newer." >&2
    return 1
  }

  local repo_root name workspace
  local -a workspaces
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
  workspaces=()
  while IFS= read -r workspace; do
    workspaces+=("$workspace")
  done < <(workspace_mounts "$repo_root")

  if ! sandbox_exists "$name"; then
    sbx create --name "$name" --template "$TEMPLATE" --kit "$KIT" \
      "$SANDBOX_AGENT" "${workspaces[@]}"
    bootstrap_sandbox "$name"
  elif [[ -n "$BOOTSTRAP_MARKER" ]] && ! sbx exec "$name" test -f "$BOOTSTRAP_MARKER"; then
    bootstrap_sandbox "$name"
  fi

  run_agent "$name" "$@"
}

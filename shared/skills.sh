#!/usr/bin/env bash
set -euo pipefail

CAVEMAN_TAG="v2.2.0"
CAVEMAN_REVISION="9aa63945a349bef17206540650db48c30fafbdf2"
SUPERPOWERS_SKILLS=(brainstorming dispatching-parallel-agents executing-plans
  finishing-a-development-branch receiving-code-review requesting-code-review
  subagent-driven-development systematic-debugging test-driven-development
  using-git-worktrees using-superpowers verification-before-completion
  writing-plans writing-skills)

shared_skills_store() {
  sbx skills ls --json | jq -er '.store | select(type == "string" and startswith("/"))'
}

ensure_shared_skills() {
  local store="$1" update="${2:-}" skill missing=false
  for skill in "${SUPERPOWERS_SKILLS[@]}"; do
    [[ -f "$store/$skill/SKILL.md" ]] || missing=true
  done
  if [[ "$missing" == true || "$update" == --update ]]; then
    sbx skills add https://github.com/obra/superpowers.git --force || return
  fi
  if [[ ! -f "$store/playwright-cli/SKILL.md" || "$update" == --update ]]; then
    sbx skills add https://github.com/microsoft/playwright-cli.git --skill playwright-cli --force || return
  fi

  # Native add cannot pin refs, and native ls ignores symlinks. Publish the
  # verified skill as a real directory, with checkout/backups OUTSIDE the store.
  local revision="" cache staging
  if [[ -f "$store/caveman/.sbx-revision" ]]; then
    revision="$(<"$store/caveman/.sbx-revision")"
  fi
  if [[ "$revision" != "$CAVEMAN_REVISION" || ! -f "$store/caveman/SKILL.md" ]]; then
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/docker-sandboxes/skills"
    mkdir -p "$cache" || return
    staging="$(mktemp -d "$cache/caveman.XXXXXX")" || return
    git clone --depth=1 --branch "$CAVEMAN_TAG" https://github.com/JuliusBrussee/caveman.git "$staging/source" || return
    [[ "$(git -C "$staging/source" rev-parse HEAD)" == "$CAVEMAN_REVISION" ]] || {
      echo 'Unexpected shared Caveman revision' >&2
      return 1
    }
    cp -R "$staging/source/skills/caveman" "$staging/skill" || return
    printf '%s\n' "$CAVEMAN_REVISION" >"$staging/skill/.sbx-revision" || return
    if [[ -e "$store/caveman" || -L "$store/caveman" ]]; then
      mv "$store/caveman" "$staging/previous" || return
      printf 'Previous Caveman skill saved at %s/previous\n' "$staging" >&2
    fi
    mv "$staging/skill" "$store/caveman" || return
  fi
  for skill in "${SUPERPOWERS_SKILLS[@]}" caveman playwright-cli; do
    [[ -f "$store/$skill/SKILL.md" ]] || {
      printf 'Missing shared skill: %s\n' "$skill" >&2
      return 1
    }
  done
}

link_shared_skills() {
  local destination="$1"
  : "${SHARED_SKILLS_ROOT:?The sandbox environment must mount the shared skills store}"
  [[ -f "$SHARED_SKILLS_ROOT/using-superpowers/SKILL.md" &&
    -f "$SHARED_SKILLS_ROOT/caveman/SKILL.md" &&
    -f "$SHARED_SKILLS_ROOT/playwright-cli/SKILL.md" ]] || {
    echo 'Shared skills mount is incomplete; run sbx-skills on the host.' >&2
    return 1
  }
  mkdir -p "$(dirname "$destination")"
  if [[ -d "$destination" && ! -L "$destination" ]]; then
    # Fresh templates may create an empty discovery directory.
    rmdir "$destination" || {
      echo "Nonempty skills directory: $destination. Recreate this sandbox for the shared-skills migration." >&2
      return 1
    }
  fi
  ln -sfn "$SHARED_SKILLS_ROOT" "$destination"
}

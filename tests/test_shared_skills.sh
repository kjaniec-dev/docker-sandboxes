#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/shared/skills.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache"
store="$tmp/store"
mkdir -p "$store"
for skill in "${SUPERPOWERS_SKILLS[@]}" playwright-cli; do
  mkdir -p "$store/$skill"
  touch "$store/$skill/SKILL.md"
done
# Only network cloning is replaced: the real installer must copy the skill
# into the native store as a directory (sbx ignores symlink entries).
git() {
  if [[ "$1" == clone ]]; then
    local target="${!#}"
    mkdir -p "$target/.git" "$target/skills/caveman/resources"
    printf 'pinned skill\n' >"$target/skills/caveman/SKILL.md"
    touch "$target/skills/caveman/resources/reference.md"
    printf 'clone\n' >>"$tmp/clones"
  elif [[ "$1" == -C && "$3" == rev-parse ]]; then
    printf '%s\n' "${MOCK_REVISION:-$CAVEMAN_REVISION}"
  else
    return 90
  fi
}
sbx() {
  echo 'Unexpected skill download' >&2
  return 91
}
ensure_shared_skills "$store"
[[ -d "$store/caveman" && ! -L "$store/caveman" ]] || {
  echo 'Caveman must be a real native-store directory' >&2
  exit 1
}
[[ -f "$store/caveman/resources/reference.md" && ! -e "$store/.sources" ]]
ensure_shared_skills "$store"
[[ "$(wc -l <"$tmp/clones" | tr -d ' ')" == 1 ]]
# A failed refresh must not report success just because old skills still exist.
status=0
ensure_shared_skills "$store" --update 2>/dev/null || status=$?
[[ "$status" == 91 ]] || {
  echo 'Skill update failure was swallowed' >&2
  exit 1
}
export SHARED_SKILLS_ROOT="$store"
link_shared_skills "$tmp/discovery/skills"
link_shared_skills "$tmp/discovery/skills"
[[ "$(readlink "$tmp/discovery/skills")" == "$store" ]]
mkdir -p "$tmp/nonempty"
touch "$tmp/nonempty/user-file"
if (link_shared_skills "$tmp/nonempty") 2>/dev/null; then exit 1; fi
[[ -f "$tmp/nonempty/user-file" ]]
# Never publish an unverified checkout.
mkdir -p "$tmp/bad-store"
for skill in "${SUPERPOWERS_SKILLS[@]}" playwright-cli; do
  mkdir -p "$tmp/bad-store/$skill"
  touch "$tmp/bad-store/$skill/SKILL.md"
done
if (MOCK_REVISION=wrong ensure_shared_skills "$tmp/bad-store") 2>/dev/null; then exit 1; fi
[[ ! -e "$tmp/bad-store/caveman" ]]
echo 'test_shared_skills.sh: PASS'

#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  case "$argument" in
    --auto|--auto=*|--no-auto|--no-auto=*) exec opencode "$@" ;;
  esac
done
exec opencode --auto "$@"

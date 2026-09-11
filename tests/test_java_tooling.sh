#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'openjdk-25-jdk-headless' "$ROOT/shared/install-system-toolchain.sh"
grep -Eq '(^|[[:space:]])maven([[:space:]\\]|$)' "$ROOT/shared/install-system-toolchain.sh"
grep -Eq '(^|[[:space:]])gradle([[:space:]\\]|$)' "$ROOT/shared/install-system-toolchain.sh"
grep -Fq '/opt/java/openjdk' "$ROOT/shared/install-system-toolchain.sh"
grep -Fq 'java --version' "$ROOT/shared/verify-toolchain.sh"
grep -Fq 'javac --version' "$ROOT/shared/verify-toolchain.sh"
grep -Fq 'mvn --version' "$ROOT/shared/verify-toolchain.sh"
grep -Fq 'gradle --version' "$ROOT/shared/verify-toolchain.sh"
grep -Fq '"25"' "$ROOT/shared/verify-toolchain.sh"

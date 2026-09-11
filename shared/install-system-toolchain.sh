#!/usr/bin/env bash
set -euo pipefail
: "${NODE_VERSION:?NODE_VERSION is required}"
: "${GO_VERSION:?GO_VERSION is required}"

export JAVA_HOME="${JAVA_HOME:-/opt/java/openjdk}"

apt-get update &&
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl wget gnupg openssh-client git git-lfs \
    ripgrep fd-find jq fzf make just unzip zip tar xz-utils tree shellcheck shfmt \
    python3 python3-venv python3-pip postgresql-client sqlite3 redis-tools \
    openjdk-25-jdk-headless maven gradle &&
  mkdir -p "$(dirname "$JAVA_HOME")" &&
  ln -sfn "/usr/lib/jvm/java-25-openjdk-$(dpkg --print-architecture)" "$JAVA_HOME" &&
  ln -sf /usr/bin/fdfind /usr/local/bin/fd &&
  rm -rf /var/lib/apt/lists/*

set -eux
arch="$(dpkg --print-architecture)"
case "$arch" in
amd64)
  node_arch="x64"
  go_arch="amd64"
  yq_arch="amd64"
  ;;
arm64)
  node_arch="arm64"
  go_arch="arm64"
  yq_arch="arm64"
  ;;
*)
  echo "unsupported architecture: $arch" >&2
  exit 1
  ;;
esac
curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"
tar -xJf "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -C /usr/local --strip-components=1
rm "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"
curl -fsSLO "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz"
rm -rf /usr/local/go
tar -C /usr/local -xzf "go${GO_VERSION}.linux-${go_arch}.tar.gz"
rm "go${GO_VERSION}.linux-${go_arch}.tar.gz"
curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}" -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq

corepack enable
corepack prepare pnpm@10 --activate
npm install -g @playwright/cli@latest
# Use the CLI's Playwright version; install browser binaries later as agent.
node "$(npm root -g)/@playwright/cli/node_modules/playwright/cli.js" install-deps chromium
npm cache clean --force

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  >/etc/apt/sources.list.d/github-cli.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh
rm -rf /var/lib/apt/lists/*

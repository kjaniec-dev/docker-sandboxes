# syntax=docker/dockerfile:1
# V3 mixins are filesystem overlays. Building from the standard shell-docker
# template keeps package installation straightforward while the kit frontend
# publishes only the changed filesystem content as the mixin layer.
FROM docker/sandbox-templates:shell-docker

USER root

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl wget gnupg openssh-client git-lfs \
      ripgrep fd-find jq fzf make just unzip zip tar xz-utils tree shellcheck shfmt \
      python3 python3-venv python3-pip postgresql-client sqlite3 redis-tools \
      openjdk-25-jdk-headless maven gradle \
 && ln -sfn /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# Native uv install; the base already provides Python.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Keep the base image's Node version. Add only the common package-manager and browser CLI.
RUN npm install -g pnpm@10 @playwright/cli@latest \
 && node "$(npm root -g)/@playwright/cli/node_modules/playwright/cli.js" install-deps chromium \
 && npm cache clean --force

COPY configure-agent.py /usr/local/lib/sbx-dev/configure-agent.py
RUN chmod 0755 /usr/local/lib/sbx-dev/configure-agent.py

USER agent

# Serena stays inside the sandbox so it only sees the mounted sandbox workspace.
RUN uv tool install serena-agent

# Common Go developer tooling. The base workload supplies Go itself.
RUN go install golang.org/x/tools/gopls@latest \
 && go install golang.org/x/tools/cmd/goimports@latest \
 && go install honnef.co/go/tools/cmd/staticcheck@latest \
 && go install golang.org/x/vuln/cmd/govulncheck@latest \
 && go install github.com/go-delve/delve/cmd/dlv@latest \
 && go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest \
 && go clean -cache -modcache

# Install Chromium into the agent user's Playwright cache so discovery matches runtime.
RUN node "$(npm root -g)/@playwright/cli/node_modules/playwright/cli.js" install chromium \
 && npm cache clean --force \
 && uv cache clean

USER root

# Make user-installed tools available without depending on shell profile loading.
RUN ln -sfn /home/agent/.local/bin/serena /usr/local/bin/serena \
 && for tool in gopls goimports staticcheck govulncheck dlv golangci-lint; do \
      ln -sfn "/home/agent/go/bin/$tool" "/usr/local/bin/$tool"; \
    done

USER agent

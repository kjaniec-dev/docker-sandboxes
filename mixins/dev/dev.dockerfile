# syntax=docker/dockerfile:1
# Build dependencies only; each workload retains its own Node and Go runtimes.
FROM node:24-trixie-slim@sha256:af02d57b57719b9657a45199a79264a9437940cd55b3c7b3fc99615654f124a0 AS node
FROM golang:1.27-trixie@sha256:f18c3d73a184fb0582828510722e723b63a93f7188d11dd223d9be6f6880e65d AS go
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS tools
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils unzip git python3 build-essential \
    fd-find fzf just shellcheck shfmt postgresql-client sqlite3 redis-tools tree \
    wget openssh-client git-lfs zip gh jq \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libdbus-1-3 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
    libasound2t64 libpango-1.0-0 libcairo2 fonts-liberation \
 && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY --from=go /usr/local/go /usr/local/go
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
ENV PATH=/usr/local/go/bin:$PATH \
    JAVA_HOME=/opt/sbx-dev/java \
    NPM_CONFIG_PREFIX=/opt/sbx-dev/npm \
    PLAYWRIGHT_BROWSERS_PATH=/opt/sbx-dev/browsers \
    UV_PYTHON_INSTALL_DIR=/opt/sbx-dev/python
RUN mkdir -p /opt/sbx-dev/bin /opt/sbx-dev/java /opt/sbx-dev/maven \
 && case "$TARGETARCH" in arm64) java_arch=aarch64; uv_arch=aarch64 ;; amd64) java_arch=x64; uv_arch=x86_64 ;; *) exit 1 ;; esac \
 && curl -fsSL "https://api.adoptium.net/v3/binary/version/jdk-25.0.5.1%2B2/linux/$java_arch/jdk/hotspot/normal/eclipse" | tar -xz -C /opt/sbx-dev/java --strip-components=1 \
 && curl -fsSL https://archive.apache.org/dist/maven/maven-3/3.10.1/binaries/apache-maven-3.10.1-bin.tar.gz | tar -xz -C /opt/sbx-dev/maven --strip-components=1 \
 && curl -fsSL https://services.gradle.org/distributions/gradle-9.9.2-bin.zip -o /tmp/gradle.zip \
 && unzip -q /tmp/gradle.zip -d /opt/sbx-dev \
 && curl -fsSL "https://github.com/mikefarah/yq/releases/download/v4.54.3/yq_linux_$TARGETARCH" -o /opt/sbx-dev/bin/yq \
 && chmod +x /opt/sbx-dev/bin/yq \
 && curl -fsSL "https://github.com/astral-sh/uv/releases/download/0.13.9/uv-$uv_arch-unknown-linux-gnu.tar.gz" | tar -xz -C /tmp \
 && cp "/tmp/uv-$uv_arch-unknown-linux-gnu/uv" /opt/sbx-dev/bin/uv \
 && /opt/sbx-dev/bin/uv python install 3.13.18 \
 && /opt/sbx-dev/bin/uv venv --python 3.13.18 /opt/sbx-dev/serena \
 && /opt/sbx-dev/bin/uv pip install --python /opt/sbx-dev/serena/bin/python serena-agent==1.7.0 \
 && ln -s ../maven/bin/mvn /opt/sbx-dev/bin/mvn \
 && ln -s ../gradle-9.9.2/bin/gradle /opt/sbx-dev/bin/gradle
RUN npm install -g pnpm@10.34.9 corepack@0.36.0 @playwright/cli@0.1.25 \
 && node /opt/sbx-dev/npm/lib/node_modules/@playwright/cli/node_modules/playwright/cli.js install chromium \
 && npm cache clean --force
# Pin Go tools to known versions and use the selected base toolchain without auto-downloading another.
RUN export GOBIN=/opt/sbx-dev/bin CGO_ENABLED=0 GOTOOLCHAIN=local \
 && go install golang.org/x/tools/gopls@v0.23.0 \
 && go clean -cache \
 && go install golang.org/x/tools/cmd/goimports@v0.52.0 \
 && go install honnef.co/go/tools/cmd/staticcheck@v0.8.2 \
 && go clean -cache \
 && go install golang.org/x/vuln/cmd/govulncheck@v1.9.0 \
 && go install github.com/go-delve/delve/cmd/dlv@v1.27.2 \
 && go clean -cache \
 && go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0 \
 && go clean -cache -modcache
RUN mkdir -p /opt/sbx-dev/node/bin /opt/sbx-dev/node/lib/node_modules \
 && cp /usr/local/bin/node /opt/sbx-dev/node/bin/node \
 && cp -a /usr/local/lib/node_modules/npm /opt/sbx-dev/node/lib/node_modules/npm \
 && cp -a /usr/local/go /opt/sbx-dev/go
COPY export-tools.py /tmp/export-tools.py
RUN python3 /tmp/export-tools.py \
 && mkdir -p /out/usr/local/bin \
 && for tool in java javac jar; do ln -s "/opt/sbx-dev/java/bin/$tool" "/out/usr/local/bin/$tool"; done \
 && chmod -R a+rX /opt/sbx-dev
FROM scratch
ENV PATH=/opt/sbx-dev/bin \
    JAVA_HOME=/opt/sbx-dev/java \
    PLAYWRIGHT_BROWSERS_PATH=/opt/sbx-dev/browsers \
    UV_NATIVE_TLS=true
COPY --from=tools /opt/sbx-dev /opt/sbx-dev
COPY --from=tools /out/ /
COPY configure-agent.py /opt/sbx-dev/configure-agent.py
COPY claude-statusline.py /opt/sbx-dev/claude-statusline.py
COPY codex-statusline.py /opt/sbx-dev/codex-statusline.py
COPY jq-guard.py /opt/sbx-dev/jq-guard.py

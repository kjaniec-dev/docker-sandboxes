FROM docker/sandbox-templates:shell-docker

ARG NODE_VERSION=24.19.0
ARG GO_VERSION=1.26.6
ARG TARGETARCH
ARG AGY_VERSION=1.1.27
ARG AGY_BUILD=5211191891591168

USER root
ENV PATH=/usr/local/go/bin:/home/agent/go/bin:${PATH}

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        agy_dir="linux-x64"; \
        agy_file="cli_linux_x64.tar.gz"; \
        agy_sha256="f874d4f6b8a73c2df660f580f25fb656fcb6e64adbfd746e6692e837fd9a20be" \
        ;; \
      arm64) \
        agy_dir="linux-arm"; \
        agy_file="cli_linux_arm64.tar.gz"; \
        agy_sha256="97fc9fe5a6067406cd02cbe4ae6e362c9623a24d33bec486911246c17ceb6a94" \
        ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/agy.tar.gz \
      "https://storage.googleapis.com/antigravity-public/antigravity-cli/${AGY_VERSION}-${AGY_BUILD}/${agy_dir}/${agy_file}"; \
    echo "$agy_sha256  /tmp/agy.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/agy.tar.gz -C /tmp; \
    install -m 0755 /tmp/antigravity /usr/local/bin/agy; \
    printf '%s\n' '#!/bin/sh' 'exec /usr/local/bin/agy "$@"' > /usr/local/bin/opencode; \
    chmod 0755 /usr/local/bin/opencode; \
    rm -f /tmp/agy.tar.gz /tmp/antigravity

COPY shared/install-system-toolchain.sh /tmp/install-system-toolchain.sh
RUN NODE_VERSION="$NODE_VERSION" GO_VERSION="$GO_VERSION" bash /tmp/install-system-toolchain.sh

COPY shared/install-user-toolchain.sh /tmp/install-user-toolchain.sh
USER agent
RUN bash /tmp/install-user-toolchain.sh

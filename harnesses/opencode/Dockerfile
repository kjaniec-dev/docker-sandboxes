FROM docker/sandbox-templates:opencode-docker

ARG NODE_VERSION=24.19.0
ARG GO_VERSION=1.26.6

USER root
ENV PATH=/usr/local/go/bin:/home/agent/go/bin:${PATH}

COPY shared/install-system-toolchain.sh /tmp/install-system-toolchain.sh
RUN NODE_VERSION="$NODE_VERSION" GO_VERSION="$GO_VERSION" bash /tmp/install-system-toolchain.sh

COPY shared/install-user-toolchain.sh /tmp/install-user-toolchain.sh
USER agent
RUN bash /tmp/install-user-toolchain.sh

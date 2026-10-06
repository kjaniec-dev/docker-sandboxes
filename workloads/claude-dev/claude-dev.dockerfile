# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:shell-docker
USER agent
# Claude's vendored ripgrep uses jemalloc built for 4 KiB pages and crashes on 16 KiB ARM64 kernels.
ENV USE_BUILTIN_RIPGREP=0
WORKDIR /home/agent/workspace
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
CMD []

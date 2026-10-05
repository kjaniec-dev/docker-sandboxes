# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:shell-docker
USER agent
WORKDIR /home/agent/workspace
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
CMD []

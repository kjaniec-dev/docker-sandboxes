# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:shell-docker@sha256:b178ca62ec2e79af2a044e3ec321bdb72188690e1c15d573ea5524b397554d3d
USER agent
WORKDIR /home/agent/workspace
# The official mixin's wrapper targets a missing extensionless file in 1.18.33.
# Prefer the working npm-generated command installed by that same mixin.
ENV PATH=/opt/opencode/bin:$PATH
COPY --chown=agent:agent opencode.json /home/agent/.config/opencode/opencode.json
COPY --chmod=755 run.sh /usr/local/bin/opencode-dev
ENTRYPOINT ["/usr/local/bin/opencode-dev"]
CMD []

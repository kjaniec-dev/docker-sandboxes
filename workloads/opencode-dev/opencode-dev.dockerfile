# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:shell-docker
USER agent
WORKDIR /home/agent/workspace
# The official mixin's wrapper targets a missing extensionless file in 1.18.33.
# Prefer the working npm-generated command installed by that same mixin.
ENV PATH=/opt/opencode/bin:$PATH
COPY --chown=agent:agent opencode.json /home/agent/.config/opencode/opencode.json
COPY --chmod=755 run.sh /usr/local/bin/opencode-dev
ENTRYPOINT ["/usr/local/bin/opencode-dev"]
CMD []

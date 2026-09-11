#!/usr/bin/env bash
set -euo pipefail

curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install serena-agent
go install golang.org/x/tools/gopls@latest
go install golang.org/x/tools/cmd/goimports@latest
go install honnef.co/go/tools/cmd/staticcheck@latest
go install golang.org/x/vuln/cmd/govulncheck@latest
go install github.com/go-delve/delve/cmd/dlv@latest
go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest

# Browser discovery uses the current user's cache. Match the installed CLI
# instead of resolving a second, potentially different Playwright version.
node "$(npm root -g)/@playwright/cli/node_modules/playwright/cli.js" install chromium

# Keep installed tools, not their build/download caches, in the image layer.
go clean -cache -modcache
uv cache clean
npm cache clean --force

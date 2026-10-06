## Shared development workflow

Use the same development workflow regardless of the active coding agent:

- Use **Superpowers** for planning, implementation workflow and verification when the relevant skills are available.
- Prefer **Context7** through the SBX MCP gateway for current library and framework documentation instead of relying on stale API memory.
- When Context7 lacks a library or product, fetch the official docs directly. IBM documentation (`www.ibm.com/docs`, `developer.ibm.com`, `cloud.ibm.com/docs`) is reachable from the sandbox.
- Prefer **Serena** for semantic code navigation and symbol-aware edits when its MCP server is available.
- Use **Playwright CLI** for browser, UI and accessibility validation when a runnable frontend exists.
- Prefer project-local package-manager, formatter, linter, build and test versions over globally installed convenience tools.
- Run the project-relevant tests, linting and formatting before reporting completion.

### Git and worktrees

- Use project-local `.worktrees/` for worktrees.
- Verify `.worktrees/` is ignored before creating a worktree.
- Never create a sibling worktree outside the mounted repository.
- When changing worktrees, point semantic tooling such as Serena at the active worktree before semantic reads or edits.

### Security

- Never commit credentials, API keys, OAuth/session state, machine-specific absolute paths or generated authentication files.
- The mounted Git repository is writable; other host paths are not assumed to exist inside the sandbox.
- Do not bypass SBX isolation by running project-aware MCP stdio servers on the host.

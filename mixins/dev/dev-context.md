## Shared development workflow

Use the same development workflow regardless of the active coding agent:

- Use **Superpowers** for planning, implementation workflow and verification when the relevant skills are available.
- Prefer **Context7** through the SBX MCP gateway for current library and framework documentation instead of relying on stale API memory.
- When Context7 lacks a library or product, fetch the official docs directly. IBM documentation (`www.ibm.com/docs`, `developer.ibm.com`, `cloud.ibm.com/docs`) is reachable from the sandbox.
- Use **Serena** by default for code navigation and editing when its MCP server is available. Fall back to `rg`/grep only when plain text search fits the case better (literal strings, logs, config, comments, non-code files, or languages Serena does not support).
- Use the full Serena toolset, not only search:
  - Navigation: `get_symbols_overview`, `find_symbol`, `find_referencing_symbols`; use `search_for_pattern` for regex search within the project.
  - Editing: `replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol`, `rename_symbol`.
  - Memory: at the start of a task, `list_memories` and `read_memory` for relevant context; when you learn something durable (architecture, conventions, commands, decisions, gotchas), save it with `write_memory` or update it with `edit_memory`, and remove stale entries with `delete_memory`.
  - Project setup: `activate_project` for the active project or worktree, and run onboarding if `check_onboarding_performed` reports it has not been done.
- Never store secrets or credentials in Serena memories.
- Use **Playwright CLI** for browser, UI and accessibility validation when a runnable frontend exists.
- Prefer project-local package-manager, formatter, linter, build and test versions over globally installed convenience tools.
- Run the project-relevant tests, linting and formatting before reporting completion.
- On ARM64, do not rely on bundled or static `rg` binaries (for example the one shipped with an agent) that assume 4 KiB pages; they crash with `<jemalloc>: Unsupported system page size` on 16 KiB kernels. Use the distro-provided `rg` from `PATH`.

### Git and worktrees

- Use project-local `.worktrees/` for worktrees.
- Verify `.worktrees/` is ignored before creating a worktree.
- Never create a sibling worktree outside the mounted repository.
- When changing worktrees, point semantic tooling such as Serena at the active worktree before semantic reads or edits.

### Security

- Never commit credentials, API keys, OAuth/session state, machine-specific absolute paths or generated authentication files.
- The mounted Git repository is writable; other host paths are not assumed to exist inside the sandbox.
- Do not bypass SBX isolation by running project-aware MCP stdio servers on the host.

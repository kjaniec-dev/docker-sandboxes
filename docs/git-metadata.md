# Writable Git metadata

The workspace bind mount includes writable `.git` metadata so agents can commit and create
project-local worktrees. A sandbox agent can therefore plant commands that a later **host** Git
invocation executes with host privileges. Git-aware shell prompts can trigger this on returning
to the terminal. `safe.directory` does not protect an owned checkout from this attack.

## Launcher checks

`bin/sbx-dev` calls `bin/audit-git.py` before any repository Git operations and again on shell exit,
including failed provisioning, failed agent sessions, INT and TERM. The shell waits for SBX
instead of replacing itself with `exec`. An unsafe preflight prevents launch; an unsafe postflight
fails a successful session. An existing nonzero child exit status is preserved (Ctrl-C reaches the
agent, and the launcher reports the agent's own exit status).

When the postflight audit fails, the launcher runs `sbx stop <name>` and renames `.git` to
`.git.sbx-quarantine-<UTC timestamp>-<pid>`, so a Git-aware prompt or IDE cannot execute planted
commands before the warning is read. Nothing is deleted or rewritten. After inspecting the
quarantined directory with trusted tools, repair it and `mv` it back to `.git`. Launching refuses to
continue while a quarantine directory exists next to the repository. A failed preflight never
quarantines anything.

The check reads configuration using Git's own parser with an explicit file and includes disabled.
It rejects local includes (including inactive `includeIf` branches), command-valued settings such
as fsmonitor, hooks paths, SSH commands, pagers, editors, filters, textconv, diff commands, merge
drivers, shell aliases, aliases injecting global Git options, configured hooks, trailers,
credential helpers, signing programs, `protocol.*.allow`, remote-helper URLs (`transport::address`,
`remote.*.vcs`, including `url.*.insteadOf` spellings), `submodule.*.update = !…` and
`sendemail`/`browser`/`man` commands. It inspects main, worktree and
submodule metadata, rejects non-sample hooks regardless of executable mode, rejects metadata
symlinks, checks administrative routing paths and detects replacement of the main `.git` directory.
It never invokes repository hooks, filters or fsmonitor to inspect those files. Diagnostics identify
the file/key without printing its potentially secret command value.

Directories under `.worktrees/` are audited because that is where agents create worktrees and where
you `cd` to review them. Each must be a genuine linked worktree: `.git` is a plain file whose
`gitdir:` points directly into this repository's `.git/worktrees/`. Nested repositories (a `.git`
directory), bare repositories, symlinks and redirected `gitdir:` links are rejected.

This deliberately rejects local Git LFS filters, Husky hooks and other local command integrations.
Trusted host-wide Git configuration is outside the local-config policy; moving commands there is
safe only when their executable files and configuration are also outside writable workspaces.

## Limits and recovery

**This is detection and launch hardening, not a complete sandbox isolation boundary.** Audits
cannot prevent concurrent host Git or shell prompts from executing commands while a sandbox can
write metadata. SIGKILL, a host crash, and background processes in a reused sandbox can bypass or
outlive the postflight check. Nested independent repositories and trusted global includes or hooks
pointing into the writable checkout, and repositories outside `.worktrees/`, are also outside this
audit's protection. Transport settings such as `http.proxy` or `http.sslVerify=false` are not
treated as commands, but a planted proxy can capture credentials that a host credential helper
sends; review `http.*` entries when inspecting a failed audit. Closing the boundary
requires separating host Git metadata from sandbox-writable metadata.
The setting policy covers known command-valued Git options; new Git command integrations require
review and corresponding regression coverage.

On failure, metadata is left intact for trusted inspection; it is not automatically deleted or
rewritten. Stop the sandbox with native `sbx stop <name>`, disable Git-aware prompts and inspect the
reported files using a trusted editor outside the checkout before running host Git again. An audit
failure does not make returning to a Git-aware prompt safe. Review local config and non-sample
hooks, repair them, then rerun `python3 /trusted/path/to/bin/audit-git.py /absolute/project/path`.

Keep the launcher checkout, its audit helper, and machine-local SBX overlays outside any workspace
mounted into an untrusted agent: a guard that the agent can edit cannot establish host trust.

Regression coverage uses disposable real Git repositories and an SBX boundary stub:
`python3 -m unittest discover -s tests -p test_behavior.py -v`.

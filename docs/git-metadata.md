# Writable Git metadata

The workspace bind mount includes writable `.git` metadata so agents can commit and create
project-local worktrees. A sandbox agent can therefore plant commands that a later **host** Git
invocation executes with host privileges. Git-aware shell prompts can trigger this on returning
to the terminal. `safe.directory` does not protect an owned checkout from this attack.

## SBX 0.50.0 host Git hardening

SBX 0.50.0 stops host Git commands **run by SBX itself** from executing programs that a sandbox
configures through the shared repository's `.git`. That removes one host-execution path, but it
does not cover host shells, Git-aware prompts, IDEs or Git commands you run yourself, which still
read the same writable metadata. The launcher audit below remains required on 0.50.0.

## Launcher checks

All `*-sbx` launchers default to `SBX_GIT_AUDIT=compatible`. This trusts repository Git
integrations: `core.hooksPath`, hook scripts (including hook symlinks), Git LFS filters, fsmonitor,
editors and other command-valued settings do not block startup or cause postflight quarantine.
The audit reads their metadata without executing them. Normal host Git can still execute those
integrations, including commands an agent adds or changes; compatible mode does not protect
against that attack. Use it for repositories whose Git integrations you trust.

Set `SBX_GIT_AUDIT=strict` to opt into the command restrictions described below, for example
`SBX_GIT_AUDIT=strict codex-sbx`. Both modes retain configuration parsing, local-include rejection,
administrative routing checks, metadata identity checks, and worktree structure checks.
Local includes remain blocked because they can override audited routing settings.

`bin/sbx-dev` calls `bin/audit-git.py` before any repository Git operations and again on shell exit,
including failed provisioning, failed agent sessions, INT and TERM. The shell waits for SBX
instead of replacing itself with `exec`. An unsafe preflight prevents launch; an unsafe postflight
fails a successful session. An existing nonzero child exit status is preserved.
Discovery and metadata identity capture share one preflight audit. While provisioning
or running SBX, the launcher forwards INT/TERM promptly and waits for the child to
finish before auditing, including metadata written during child shutdown. A child
that handles a signal and exits successfully keeps its successful status unless
the audit fails. The execution helper restores interactive signal dispositions
that Bash otherwise ignores for asynchronous jobs, and preserves standard input.

When the postflight audit fails, the launcher runs `sbx stop <name>` and renames `.git` to
`.git.sbx-quarantine-<UTC timestamp>-<pid>`, including the `.git` entries of repositories and linked
worktrees under `.worktrees/`, so a Git-aware prompt or IDE cannot execute planted
commands before the warning is read. Nothing is deleted or rewritten. After inspecting the
quarantined directory with trusted tools, repair it and `mv` it back to `.git`. Launching refuses to
continue while a quarantine directory exists next to the repository. A failed preflight never
quarantines anything.
Quarantine protects the main repository first and attempts descendants independently. A permission
or traversal failure is reported without preventing other repositories from being quarantined;
successfully moved paths are printed even if another entry fails.
Only metadata paths actually moved during the current quarantine pass are excluded from traversal.
Pre-existing directories named `.git.sbx-quarantine-*` are traversed to quarantine any active `.git`
entries hidden inside. Do not run Git or use a Git-aware prompt inside a quarantine directory before
manually inspecting its configuration and hooks with trusted tools.

The check reads configuration using Git's own parser with an explicit file and includes disabled.
Both modes reject local includes (including inactive `includeIf` branches). Strict mode also rejects command-valued settings such
as fsmonitor, hooks paths, SSH commands, pagers, editors, filters, textconv, diff commands, merge
drivers, shell aliases, aliases injecting global Git options, configured hooks, trailers,
credential helpers, signing programs, `protocol.*.allow`, remote-helper URLs (`transport::address`,
`remote.*.vcs`, including `url.*.insteadOf` spellings), `submodule.*.update = !…` and
`sendemail`/`browser`/`man` commands, absolute SMTP executable paths, manual/browser executable
paths and template directories. Ordinary remote URLs and URL rewrites remain usable.
It inspects main, worktree and submodule metadata, rejects metadata symlinks outside the compatible
mode's hooks exception, checks administrative routing paths and detects replacement of the main
`.git` directory. Strict mode rejects non-sample hook files regardless of executable mode.
Real hook subdirectories can store disabled hooks; strict mode still checks their contents for symlinks.
Linked worktrees outside the main checkout remain supported when launching from the main
checkout. Their administrative `gitdir` files are backpointers and are never followed to external
files. Local `config.worktree` files are still audited; forward routing escapes are rejected,
and stale or empty `commondir` targets receive an explicit diagnostic.
Discovery and the audited directory identity come from one `--discover-identity` invocation,
which emits a JSON array containing the repository root and metadata identity.
It never invokes repository hooks, filters or fsmonitor to inspect those files. Diagnostics identify
the file/key without printing its potentially secret command value or URL rewrite base.

Directories under `.worktrees/` are audited because that is where agents create worktrees and where
you `cd` to review them. Names and grouping depth do not matter. A linked worktree has a plain
`.git` file whose `gitdir:` points directly into this repository's `.git/worktrees/`. Independent
repositories with a `.git` directory are also supported: their configuration, hooks and administrative
metadata receive the same audit as the main repository. Traversal continues through repository sources
to find further nested repositories, without following source symlinks. Bare repositories,
symlinks and redirected `gitdir:` links are rejected. Quarantined metadata anywhere in the audited
`.worktrees/` grouping prevents launch until it has been inspected and restored or removed.

Strict mode deliberately rejects local Git LFS filters, Husky hooks and other local command integrations.
Trusted host-wide Git configuration is outside the local-config policy; moving commands there is
safe only when their executable files and configuration are also outside writable workspaces.

## Limits and recovery

**This is detection and launch hardening, not a complete sandbox isolation boundary.** Audits
cannot prevent concurrent host Git or shell prompts from executing commands while a sandbox can
write metadata. SIGKILL, a host crash, and background processes in a reused sandbox can bypass or
outlive the postflight check. Independent repositories outside the audited `.worktrees/` tree and
trusted global includes or hooks pointing into the writable checkout are also outside this
audit's protection. Transport settings such as `http.proxy` or `http.sslVerify=false` are not
treated as commands, but a planted proxy can capture credentials that a host credential helper
sends; review `http.*` entries when inspecting a failed audit. Closing the boundary
requires separating host Git metadata from sandbox-writable metadata.
The strict setting policy covers known command-valued Git options; new Git command integrations require
review and corresponding regression coverage.

On postflight failure, the launcher stops the sandbox and quarantines metadata as described above;
preflight failures leave metadata in place. Disable Git-aware prompts and inspect the reported files
using a trusted editor outside the checkout before running host Git again. A preflight audit failure
does not make returning to a Git-aware prompt safe. Review local config and non-sample hooks,
repair them, restore quarantined metadata to `.git` when applicable, then rerun
`python3 /trusted/path/to/bin/audit-git.py /absolute/project/path`.
The standalone helper defaults to strict checks. Add `--allow-integrations` before the project path
to use the launcher's default compatible policy; `--strict` selects strict checks explicitly.

Keep the launcher checkout, its audit helper, and machine-local SBX overlays outside any workspace
mounted into an untrusted agent: a guard that the agent can edit cannot establish host trust.

Regression coverage uses disposable real Git repositories and an SBX boundary stub:
`python3 -m unittest discover -s tests -p test_git_audit.py -v` and
`python3 -m unittest discover -s tests -p test_behavior.py -v`.

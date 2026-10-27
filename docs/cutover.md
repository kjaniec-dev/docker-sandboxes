# V3 cutover evidence

The repository now contains the V3 architecture described by `AGENTS.md` and the environment files.
Legacy harnesses, shared launch/rebuild/skills helpers, per-agent rebuild commands, scaffold generator,
policy wrapper, tar exports, wiring tests and obsolete documentation have been removed.
Git history is the archive; no compatibility tree remains.

Verification machine: macOS/arm64, SBX **0.46.0**, Sandbox Kit V3. The native builder was reprovisioned
with its official kit and a 32 GiB volume after its default cache volume ran out of space.
Existing user project sandboxes were preserved. Disposable test sandboxes were removed.

## Evidence before removal

`tests/validate.sh` passed 32 behavioral tests, four native source kit builds/inspections and all
seven native environment plans. Runtime smoke covered the following:

| Environment | Tools/browser/skills/context/MCP | Fresh, stop/start, delete/recreate | Completed model request |
| --- | --- | --- | --- |
| Personal Codex | Passed | Passed | Passed at all three stages |
| Personal Antigravity | Passed | Passed | Not checked; no Google credential available |
| Personal Junie | Passed | Passed | Not checked; no authorized Junie credential binding |
| Personal Claude | Passed | Passed | Passed at all three stages |
| Personal OpenCode | Passed | Passed | OpenCode Go authentication not checked |
| Client Copilot | Passed | Passed | Failed authentication; native credential binding unverified |
| Client Claude Vertex | Native environment plan passed | Deferred by user | Deferred by user |

The infrastructure checks launch Chromium, verify Java 25/javac, Python/uv, Go, Node and developer
commands, check read-only native skills and generated context, perform a real sandbox-local Serena
symbol lookup, and call Context7 through the native MCP gateway. The model probe requires a completed
response with the correct computed answer; an echoed prompt or an error cannot pass.

## Demonstrated integration gaps

These are historical cutover observations on SBX 0.46, not assertions that the same upstream bugs
remain on every supported release. The [workaround register](workarounds.md) tracks active shims,
their current evidence, removal conditions and probes. A successful smoke run with a workaround
enabled does not show whether the workaround is still necessary.

- SBX 0.46 created Antigravity's skills ancestors as root-owned directories. A native root install
  hook changes ownership of those two directories so the official startup hooks can write configuration.
- Codex does not discover SBX's instruction file above the mounted Git root. Its global instruction
  path points to the native generated profile; project instruction files remain intact.
- Junie's official kit has no gateway registration hook. The local adapter registers the native gateway
  URL alongside sandbox-local Serena in Junie's supported configuration.
- Some official bases ship uv/uvx binaries that abort. The native install hook activates the baked
  working binaries only when the version probe fails.
- The official OpenCode 1.18.33 mixin wrapper points to a missing extensionless executable.
  The thin workload's native PATH selects the working npm-generated executable from the same mixin.
- Official Antigravity/OpenCode gateway hooks replace malformed MCP arrays or null with a new map.
  The original exported jq launcher validated their exact merge command and two configuration paths.
  A native install hook selects it for those agents; invalid configuration fails before the original
  merge/move sequence can overwrite it. Other jq commands retain their normal behavior. The native
  lifecycle API exposes dependency ordering, without a pre-hook priority for an unchanged official
  workload, so this bridges demonstrated agent behavior rather than replacing SBX lifecycle.
- The full OpenCode composition exceeded the runtime's 4096-byte kit-lock label limit. Native wildcard
  rules group GitHub, Golang and Ubuntu vendor subdomains, and redundant GitHubusercontent entries
  were removed. All previously listed hosts remain covered; vendor subdomain access is broader.
  Duplicated skills declarations were removed from the thin workloads; the dev mixin owns that capability.

Native SBX continues to own lifecycle, skills storage, remote MCP hosting, credentials and composition.
The repository adds no native lifecycle emulation or compatibility layer.

## Verification after removal

Final validation on **2026-10-06** passed **34 behavioral tests**, four native source kit
builds/inspections and seven environment plans. All six non-Vertex environments passed fresh,
stop/start and delete/recreate smoke on the cleaned tree. Codex and personal Claude also completed
authenticated model requests at all three stages. Antigravity/OpenCode rejected malformed MCP
merges without data loss at every stage. Disposable test sandboxes were removed.

The final remaining variant builds initially stopped with exit 137 during concurrent cold builds.
A single native rebuild succeeded using the existing cache; no production workaround was added.
Runtime logs and task completion records are retained under the ignored `.superpowers/` directory.

Vertex runtime and ADC/WIF testing remain deferred at the user's request. Copilot's earlier model
probe failed authentication. Fresh SBX output reports no authorized Copilot credential binding;
a stored GitHub credential alone does not authorize injection. Resolve this using the client
machine's approved native credential binding; the probe does not prove that the stored token is invalid.
Antigravity and OpenCode Go model authentication still require their machine-specific credentials.
Junie's later client correction and provider response are recorded below.

Source kit and environment edits require native sandbox recreation: `sbx env run` reattaches existing
sandboxes without provisioning them again. Pre-rewrite sandboxes must be recreated before using the new
composition; the launcher does not migrate or delete them automatically.

Final review deferred one minor test improvement: asserting that a sandbox-local marker survives
stop/start and disappears after recreation. At cutover, smoke checked runtime behavior at every stage,
but did not independently assert persistence of arbitrary sandbox-local state.
This deferred check was subsequently implemented in `tests/smoke-check.py` and is included in
the later lifecycle matrices recorded below.

## Junie client correction, 2026-10-06

A real interactive Junie 3294.5 session exposed two gaps that the original Python gateway probe
did not cover: its JVM MCP transport ignored HTTP_PROXY and tried to resolve the proxy-only gateway
hostname, and its official workload omitted `ingrazzio-cloud-prod.labs.jb.gg` from provider egress.
Native JVM proxy properties in the Junie environment fix the transport; the declaration-only
`workloads/junie-dev` mixin adds that exact provider host without replacing the official workload.
The existing user sandbox received a sandbox-scoped native allow rule. Junie now launches via
native `sbx env exec`, which applies the revised JVM environment to new sessions without recreation.

The new smoke check launches Junie's actual interactive MCP client without making a model request.
It rejected the old configuration with UnknownHostException, and the corrected client initialized
the native gateway. The initial authentication failure sent only the installed kit's `proxy-managed`
sentinel. The user then stored a native custom secret for both provider hosts.
The official kit replaces custom `JUNIE_API_KEY` placeholders with `proxy-managed`, so the launcher
passes the public native placeholder explicitly to `sbx env exec`. A small Junie-only metadata
adapter selects sandbox scope before global scope and never retrieves the real token. Native V3
refuses a second owner of the official kit's Junie credential; no duplicate credential is retained.

The corrected request reached the backend with the user's stored token and returned
`Insufficient account balance. All tokens in your account have been spent.` Thus the completed
model response remains unverified because the provider account has no available balance.

Final Junie correction validation passed **38 behavioral tests**, **five** native kit inspections
and all seven environment plans. Junie infrastructure smoke, including its actual MCP transport,
passed fresh, stop/start and delete/recreate. The public launcher also completed a real `--help`
invocation against the preserved user sandbox. Disposable test sandboxes were removed and the
temporary unused Junie service binding was pruned; the user's global custom secret was retained.

## Vertex ADC correction, 2026-10-06

Client Claude started on SBX 0.47.0 with Vertex selected but could not load Google credentials.
The host already had approved user ADC; the sandbox had neither the standard ADC file nor
`GOOGLE_APPLICATION_CREDENTIALS`. A native read-only mount of that single file to the standard
agent-home ADC path fixed credential visibility without recreating the user's sandbox.

The machine-local client overlay now uses a native `postCreate` host hook, guarded by
`SBX_AGENT=claude-dev`, to restore the same mount after recreation. No credential content was copied
into the repository, no new keys or login flow were created, and Copilot received no ADC mount.
The generic approved-user-ADC configuration is documented in `docs/client-vertex.md`.

The existing client Claude sandbox completed a Vertex model response. Full client Claude smoke
then passed tooling, Chromium, skills, context, Serena, Context7, lifecycle and authenticated model
responses at fresh, stop/start and delete/recreate stages. The disposable sandbox was removed.
The existing ADC mount was confirmed read-only, Copilot credential isolation was checked, and
38 offline behavior tests passed. Other approved client WIF variants remain unverified.

## Haiku regional override, 2026-10-06

Client Claude used the `eu` multi-region default, but Haiku 4.5 required `europe-west1`.
The machine-local client overlay now declares `VERTEX_REGION_CLAUDE_HAIKU_4_5=europe-west1`
without changing the default region, ADC or other model regions.

Client Claude now launches through native `sbx env exec` so the merged environment applies to
new sessions in existing sandboxes. Its original workload permission flag, project working
directory and individual agent arguments are preserved. Other launch paths remain unchanged.
A completed Haiku 4.5 response was verified in `europe-west1` with the default still `eu`.

Validation passed 40 behavioral tests, five native kit inspections and all seven environment
plans. Full authenticated client Claude smoke passed fresh, stop/start and delete/recreate,
preserving default-model behavior and ADC access with the new override. Disposable test sandboxes
were removed; the user's existing sandboxes were preserved.

## Official kit pins, 2026-10-07

SBX 0.47.0 rejected `docker/sbx-kit-codex:latest` with the same unknown
`agent-context.directory` field as the latest Claude mixin. The other four floating official kit
references still parsed successfully. All environments now use fixed official OCI digests:
the existing Claude 2.1.285 pin, Codex 0.159.2, Antigravity kit 1.0.0, Junie 26.9.21,
OpenCode 1.18.33 and Copilot 1.0.86. No official descriptor was copied or modified.

Full `tests/validate.sh` passed on SBX 0.47.0: 40 behavior tests, native local kit builds and all
seven environment plans. Validation used `env -u CODEX_HOME` because the host's exported
Codex home otherwise overrides the adapter tests' temporary fixtures.

The fresh Codex smoke initially rejected its working distro `/usr/bin/rg` solely because the
check required the shared wrapper path. Both known distro entrypoints are now accepted;
the actual `rg --version` and `rg --files` probes remain, including on the verified 16 KiB ARM64
kernel. The final Codex smoke passed tooling, Chromium, native skills/context, Serena, Context7
and fresh/stop-start/delete-recreate stages. Model authentication was not checked in this run.
The 40 offline tests passed again after the smoke assertion correction. Test sandboxes were removed.

## SBX 0.48 migration preparation, 2026-10-14

The [official 0.48 release notes](https://github.com/docker/sbx-releases/releases/tag/v0.48.0)
confirm that `--detached` and environment `--auto-approve` are rejected and that `sbx ls --json`
returns a direct array. The launcher now uses `--detach`; smoke uses `--detach --force` and
validates the direct array before creation and after removal. Both launcher and native validation
require stable SBX 0.48.0 or newer through a shared standard-library Python version check.

`tests/validate.sh --offline` passed **62 tests**. New regression tests exercise the real launcher
and smoke orchestration against a controlled external CLI boundary. They cover the version floor,
structured version documents, the new flags, fresh/restart/recreate sequencing, cleanup, malformed
inventory, occupied names and a sandbox still listed after removal. These are offline contract
checks; sandbox infrastructure, providers and the native runtime were not exercised.

The host remains on **SBX 0.47.0**, revision `0411f50ee4700fe7bd37e6e7e3aced563e850ca9`.
Native kit validation and the seven-environment runtime smoke matrix require a 0.48 host.
`tests/validate.sh` also passed all 62 behavior tests, then exited **1** at the version guard:
`Docker Sandboxes 0.48.0+ is required (observed: 'v0.47.0')`. Native builds/plans and runtime
smoke were not run on the unsupported host.
The version check uses the observed `sbx version --json` field `client.version`; it does not
depend on the CLI's changing human-readable output or an available server. The 0.48 changelog's
structured-output migration table does not list a version schema change. Actual 0.48 version JSON
has not been observed: a temporary copy of the official Darwin/arm64 release matched GitHub's
archive checksum, but macOS reported an invalid code signature and killed even `version`.
No host installation, settings, credentials or existing user sandboxes were changed.

SBX 0.48 supports `agent-context.directory`, so the original reason for older Claude/Codex pins
is removed. All digests remain until replacement kits pass native validation and their profile's
runtime smoke, including client Claude. Live Docker Hub metadata identified Claude mixin 2.1.292
and Codex 0.162.1 as candidates; the `latest` tags pointed to different digests at inspection time.
Choose and verify a replacement digest explicitly rather than treating `latest` as the newest
numbered release. Native `SBX_AGENT` values and newer capability groups remain a separate follow-up.

## Official kit refresh on SBX 0.48, 2026-10-15

The host CLI and daemon now both report **0.48.0**, revision
`5caf923e0587d376848f6f388eca3e0f5ca00e2d`. Real `version --json` confirms the shared
version check's `client.version` contract. Live Docker Hub tag and OCI descriptor inspection
selected the following official artifacts; the environment files retain their exact digests.

| Agent | Selected version | Selection |
| --- | --- | --- |
| Claude, personal and client | 2.1.292 | Newest numbered release; `latest` still points to 2.1.291 |
| Codex | 0.162.1 | Newest numbered release; compatible optional interactive sessions |
| OpenCode | 1.18.33 | Existing digest still matches official `latest` |
| Antigravity | Kit 1.0.0 | Existing digest still matches official `latest`; CLI can self-update |
| Junie | 26.9.21 | Existing digest still matches official `latest` |
| Copilot | 1.0.86 | Existing digest still matches official `latest` |

The first native Codex creation rejected the official `latest` artifact (0.160.1): it declares
`com.docker.sandbox/agent-interactive-sessions@1` as required, which this daemon does not support.
The official 0.162.1 descriptor marks that capability optional. Native plans alone did not detect
the incompatibility. No official descriptor was copied or patched.

The newer Claude/Codex kits declare their native context directories as `~/.claude` and `~/.codex`.
The Codex adapter no longer creates a symlink to workspace-ancestor instructions. Smoke now checks
the actual native `CLAUDE.md`/`AGENTS.md` files for the composed shared dev context. Regression tests
preserve native Codex instructions and reject an ancestor-only context for these kits.

Smoke cleanup now confirms absence after a failed removal before deleting a workspace. If removal
reports success but the following inventory fails, is malformed or still lists the sandbox, it
retains the workspace and reports failure. Tests cover these uncertain-removal cases.

The shared dev rebuild exhausted the existing builder's engine-store volume. Only the regenerable
native builder and its cache were removed, then recreated from the official builder kit with a
**64 GiB** volume. The subsequent cold Go compilation ended with code 137 and a stopped builder;
the official builder was then provisioned with **16 GiB RAM** as well. Project sandboxes were
excluded from both operations.

Client Claude runtime is excluded at the user's request; verify its native plan only. This session
does not have the client's approved project, region or machine-local host-authentication overlay.
Raw registry evidence and native logs are retained in `.superpowers/048-latest-20261015/`.

Final `tests/validate.sh` passed **71 regression tests**, **five native source kit inspections**
and **all seven environment plans** after the rebuild. The runtime matrix on the final tree passed:

| Environment | Tools/browser/skills/context/MCP | Fresh, stop/start, delete/recreate | Completed model request |
| --- | --- | --- | --- |
| Personal Codex 0.162.1 | Passed | Passed | Passed at all three stages |
| Personal Claude 2.1.292 | Passed | Passed | Passed at all three stages |
| Personal OpenCode | Passed | Passed | Not checked |
| Personal Antigravity | Passed | Passed | Not checked |
| Personal Junie | Passed, including actual JVM MCP transport | Passed | Not checked |
| Client Copilot | Passed | Passed | Not checked |
| Client Claude Vertex 2.1.292 | Native plan only (`validation-project`, `us-east5`) | Excluded by user | Excluded by user |

The final inventory contained none of this run's disposable smoke sandboxes. Existing project
sandbox IDs were unchanged. The builder was stopped after testing to release its memory while
retaining its cache. Existing project sandboxes still need deliberate recreation to receive the
new pinned kits and native context composition; the update did not recreate them automatically.

## Workload-provided ripgrep, 2026-10-15

The shared dev mixin no longer installs, copies or wraps ripgrep. Workload base images
supply `/usr/bin/rg`; smoke requires that path and rejects copies under `/opt/sbx-dev`.
Claude's `USE_BUILTIN_RIPGREP=0` override and the blanket instruction against bundled
ripgrep were removed after testing the current official Claude 2.1.292 artifact.

A disposable Claude sandbox on SBX 0.48 reported a **16384-byte kernel page size** and
working workload `/usr/bin/rg` **15.1.0**. An authenticated Claude request with explicit
`--tools Grep` found the fixture `needle.txt:1:native-ripgrep-probe`, first with
`USE_BUILTIN_RIPGREP=1`, then with the variable absent. Both returned a successful
tool result and completed model response; the old page-size crash did not reproduce.
This verifies the selected kit and machine, not every bundled ripgrep release.

Final `tests/validate.sh` passed **71 regression tests**, **five native kit inspections**
and **seven environment plans**. All six non-Vertex environments passed infrastructure
and lifecycle smoke at fresh, stop/start and delete/recreate stages, including the
workload-ripgrep assertions. These smoke runs did not request model responses; the
authenticated Claude Grep probes above were separate. Client Claude runtime remains
excluded. All seven disposable probe/smoke sandboxes were removed, and the native builder
was stopped again while retaining its cache.

## SBX 0.49.1 migration, 2026-10-21

The host CLI and daemon both report **0.49.1**, revision
`c5b19951af121b439800029695f88bf1139a0b0b`. The launcher and native validation now require
0.49.1 or newer. Existing official kit pins and Claude, Junie and OpenCode adapters are retained.

The [0.49.1 release notes](https://github.com/docker/sbx-releases/releases/tag/v0.49.1)
advertise daemon-free local kit inspection and validation. Actual checks with both
`sbx kit inspect --offline` and `sbx kit validate --offline` reject this repository's V3 source
kits with `this load path has no kit builder configured`. This also affects kits without a
Dockerfile, such as `mixins/vertex`; setting `SBX_KIT_BUILDER=sandbox` does not enable a builder
on the offline load path. Offline support therefore cannot replace native source-kit builds.
No V2 descriptors, generated copies of the source kits, or error-suppression fallback were added.

Smoke now checks Git ignore behavior inside each fresh, restarted and recreated sandbox.
The disposable primary repository contains `.worktrees/` ignored through `.gitignore` and an
existing `.sbx-host-ignored/marker` ignored only by the host repository's `.git/info/exclude`.
Regression tests reject loss of either ignore decision.

Both `tests/validate.sh --offline` and full `tests/validate.sh` passed **74 behavioral tests**.
The full native run also passed **five source kit inspections** and **all seven environment plans**.
CI retains the lightweight offline behavior suite without installing SBX: installing a CLI just to
check `version --json` would not validate these source kits. Actual 0.49.1 version JSON was checked
against the launcher's version contract on the host.

Client Claude Vertex runtime remains excluded at the user's request; only its native plan is
checked using `validation-project` and `us-east5`. No client overlay, approved project or region
is configured on this host for a runtime test.

The completed runtime matrix on **2026-10-22** passed tools, Chromium, read-only skills, native
agent context, sandbox-local Serena, Context7 and both Git ignore assertions at every stage.
Junie also passed its actual JVM MCP transport check at all three stages. These smoke runs made
no model requests, so model authentication was not checked.

| Environment | Fresh, stop/start, delete/recreate |
| --- | --- |
| Personal Codex | Passed |
| Personal Claude | Passed |
| Personal OpenCode | Passed |
| Personal Antigravity | Passed |
| Personal Junie | Passed |
| Client Copilot | Passed |
| Client Claude Vertex | Native plan only; runtime excluded by user |

The first Claude attempt passed fresh and restart checks, then failed during recreation with
Docker Hub access and Keychain errors across the session interruption. After recovery, a complete
retry passed. The retained temporary workspace was removed after native inventory confirmed that
the interrupted attempt's sandbox was absent.

Final inventory contained none of the disposable smoke sandboxes. All **nine** pre-existing
project sandbox names and IDs were preserved; no project sandboxes were recreated. The native
builder was returned to its original stopped state while retaining its build cache.

Raw migration logs are retained in `.superpowers/049-upgrade/`.

## SBX 0.49.2 security baseline, 2026-10-22

The [0.49.2 release](https://github.com/docker/sbx-releases/releases/tag/v0.49.2) supersedes
the 0.49.1 CLI minimum following the eMudhra CA compromise. The launcher, validation and
repository instructions now require **0.49.2+**. Regression coverage rejects stable 0.49.1 and
the 0.49.2 prerelease while accepting stable 0.49.2 and newer versions.

The host CLI and daemon both report **0.49.2**, revision
`5d40fd43027b33ed1f1a39c14fb07e2503d6998f`. Homebrew's installer SHA-256 matches the official
release asset (`98b6b157963e5357e6e38388d06ec3f6a5912fa3c9710e05af246b2341a0ebbc`).
Local Go build information confirms that the installed SBX executable was built with **Go 1.27.3**.
After the required daemon restart, both previously running Claude projects were confirmed running
with their original VM IDs.

This change does **not** certify existing sandbox trust stores as remediated. No CA package
updates, runtime replacements or project VM recreation were performed as part of the CLI upgrade.
Official kit digests and custom image build inputs remain unchanged; `pullPolicy: always` cannot
refresh an immutable digest. The [CA maintenance guide](ca-maintenance.md) documents the separate
package/runtime maintenance and refreshed-image paths required by Docker's security advisory.

Source-form offline inspection remains unsupported: on 0.49.2, all five source kits still fail
`sbx kit inspect --offline` with `this load path has no kit builder configured`. CI therefore
keeps its existing daemon-free behavioral suite without installing the CLI.

Both offline and full native validation passed **74 tests**. The native run also passed **five
source kit inspections** and **seven environment plans**. All six non-Vertex environments
passed fresh, stop/start and delete/recreate smoke on 0.49.2 (**18 stages**), including workspace
ignore preservation, tools/browser/skills/context, Serena and Context7. Junie passed its JVM MCP
transport check at all three stages. Model requests were not tested; Vertex remained plan-only.

A read-only audit of one existing Claude VM found CA package `20260601~26.04.1`, Java `25.0.4.1`,
Node `22.22.1`, Go `1.26.0`, uv `0.9.26` and certifi `2026.07.22`. This concrete snapshot is why
the CLI upgrade is not reported as complete VM trust-store remediation; package and independent
runtime maintenance remain separate work.

Final inventory preserved the names, IDs and running/stopped state of all **ten** existing
project sandboxes. No disposable smoke sandboxes remained, and the builder was stopped as before.

Raw 0.49.2 logs are retained separately in `.superpowers/0492-upgrade/`; the 0.49.1 matrix above
remains historical evidence for that release.

## Review hardening verification, 2026-10-22

The current review changes passed `tests/validate.sh --offline` with **94 tests**, ShellCheck,
Ruff correctness checks and `git diff --check`. Real-Git launcher regressions cover fsmonitor
execution before index reads, command configuration and aliases, includes, worktree/submodule
metadata routing, non-sample hooks, post-session mutations, child failures and TERM. These are
detection checks; [writable Git metadata remains a shared host-execution risk](git-metadata.md).

Full `tests/validate.sh` passed all **five source kit inspections** and **seven environment plans**.
The rebuilt shared mixin passed `tests/smoke.sh` for **Antigravity, OpenCode and Junie**, each through
fresh launch, stop/start and delete/recreate (**nine stages**). Antigravity/OpenCode ran the
installed official gateway hooks against malformed fixtures without data loss. Junie's actual
JVM client initialized its MCP gateway at every stage using proxy settings derived from native
SBX runtime values. Native verification did not make authenticated model requests or repeat the
remaining agents' runtime matrix. No disposable smoke sandboxes remained afterward.

The [workaround register](workarounds.md) records retirement conditions. Passing smoke with the
ownership/thin-workload workarounds enabled does not establish that upstream still needs them.


## Official kit refresh on SBX 0.49.2, 2026-10-27

Live Docker Hub tag enumeration and OCI descriptor inspection checked all six selected official
repositories. Each `latest` tag matched its newest numbered stable release at inspection time.
The environment files retain immutable top-level OCI index digests, with linux/arm64 and
linux/amd64 support; no official descriptor was copied or patched.

| Agent | Previous selection | Selected version | Result |
| --- | --- | --- | --- |
| Claude, personal and client | 2.1.292 | 2.1.310 | New artifact |
| Codex | 0.162.1 | 0.164.0 | New artifact |
| OpenCode | 1.18.33 | 1.19.4 | New artifact |
| Antigravity | Kit 1.0.0 | Kit 1.0.0 | Already newest official artifact; digest unchanged |
| Junie | 26.9.21 / 3294.5 | 26.9.21 / 3294.5 | Already newest official artifact; digest unchanged |
| Copilot | 1.0.86 | 1.0.86 | Already newest official artifact; digest unchanged |

The selected Claude, Codex and OpenCode descriptors provide optional agent-context@2 plus an
agent-context@1 fallback, without adding unsupported required capabilities. Actual native creation
on CLI/daemon 0.49.2 succeeded. OpenCode's composed instructions now live at
`~/.config/opencode/AGENTS.md`; smoke checks and context regression tests require that native file
and reject an ancestor-only substitute. A disposable probe confirmed the file contains the shared
dev context link. No agent configuration workaround was added.

Final `tests/validate.sh` passed 141 regression tests, five native source kit inspections and all
seven environment plans. Fresh, restart and delete/recreate infrastructure smoke passed for
personal Claude, Codex, OpenCode, Antigravity and Junie, and client Copilot. These runs checked the
shared tooling, Chromium, read-only skills, native context, sandbox-local Serena, Context7 gateway,
workspace ignores and lifecycle persistence. The initial OpenCode smoke failure was the old
ancestor-context test expectation; the corrected native-path check passed the complete lifecycle.
Client Claude received the new pin and passed its native plan only: the host has no approved
Vertex project, region or local auth overlay for a runtime test.

Separate minimal native probes confirmed installed Claude 2.1.310, Codex 0.164.0 and OpenCode 1.19.4.
Claude and Codex completed verified authenticated model requests. OpenCode's request reached its
provider but failed with HTTP 401 `api_key_expired`; its provider credentials were not changed.
This credential failure is independent of the successful kit infrastructure and lifecycle checks.

A missing native builder was provisioned with 16 GiB RAM and a 64 GiB engine-store volume.
The shared dev kit was cold-built through native SBX; subsequent validation used its cache.
The builder was stopped after compilation, retaining its cache. Disposable test VMs were removed
with absence verification. Logs and registry evidence live under `.superpowers/kit-refresh-20261027/`.

Existing project sandboxes are not refreshed by editing these pins. No project sandbox was
removed or recreated during this validation. Old-to-new disposable state-transfer canaries passed
for Claude 2.1.292 → 2.1.310 and Codex 0.162.1 → 0.164.0: actual conversations resumed with the same
session IDs and recalled hidden tokens while newly generated settings/auth remained intact.
Native `sbx cp` starts a stopped source and remaps downloaded/uploaded ownership to host numeric
IDs, so a verified restore requires targeted ownership repair on the transferred state paths.
These synthetic tests do not establish complete preservation of arbitrary custom real-project
state. Existing VM replacement requires a separate backup and maintenance decision; it must not
be inferred from a successful pin refresh or from a same-name recreate.

## SBX 0.50.0 security baseline, 2026-10-27

The [0.50.0 release](https://github.com/docker/sbx-releases/releases/tag/v0.50.0), published
2026-10-26 as a stable release, hardens host execution: host Git run by SBX no longer executes
programs a sandbox configures through the shared `.git`, `sbx cp` blocks further symlink escapes
through alternate host paths, browser/clipboard/self-update helpers run only from trusted system
locations, MCP OAuth blocks cross-origin credential redirects, and local source kits are reused only
when their digests match recorded builds. The launcher, validation and repository instructions now
require **0.50.0+**. Regression coverage rejects stable 0.49.2 and the 0.50.0 prerelease while
accepting stable 0.50.0 and newer versions.

Repository impact:

- **Git audit is retained.** The host Git fix covers Git invocations made by SBX itself. Host shells,
  Git-aware prompts, IDEs and manual `git` commands still read the writable shared metadata; see
  [writable Git metadata](git-metadata.md#sbx-0500-host-git-hardening).
- **`sbx exec` exit status 125** now means SBX could not start the command, for example because the
  sandbox does not exist. `tests/smoke.sh` reports this separately from a failed in-sandbox check or
  model request. The launcher passes child status through unchanged.
- **Environment MCP commands** need host execution approval and are disabled by
  `--skip-host-commands`. `env/common.sbxenv.yaml` declares only the remote Context7 URL and Serena
  stays sandbox-local, so no environment declares a host MCP command.
- **Local source kits rebuild once** after the upgrade because recorded digests are now verified.
  Expect the first `tests/validate.sh` and launch of each profile to rebuild `mixins/dev` and the
  thin workloads in the native builder.
- **Persistent kit volumes** survive kit updates and same-name delete/recreate, but only for sandboxes
  created on 0.50.0+. This repository declares none. Smoke's delete/recreate stage requires the
  home-directory marker to disappear; a failure there after the upgrade means a selected official
  kit now persists that path and must be investigated, not suppressed.
- **Host mounts** (`host-mount@1`, `--mount`, `mounts:` in environment files) are not used. A future
  `mixins/dev` mount must be declared by the kit; undeclared targets are rejected.
- Existing project sandboxes keep their previous storage semantics and are not recreated by this change.

The version floor checks `client.version` only, because `sbx version --json` must work without a
running daemon (the offline suite relies on this). A CLI/daemon mismatch is not checked by this
repository. Verify on a 0.50.0 host whether the CLI replaces or refuses an older running daemon
(`sbx version --json` after upgrading, before stopping it) and record the observed behavior here;
add a server-version check only if the daemon can keep running mismatched. `tests/smoke.sh` now
applies the same floor before creating any sandbox.

**Native verification is pending.** These changes passed `tests/validate.sh --offline`
(**142 tests**), ShellCheck and Ruff in an environment without SBX. Before merging, run on a
0.50.0 host: full `tests/validate.sh` (five source kit inspections, including the one-time rebuild,
and seven environment plans), then the complete fresh, stop/start and delete/recreate smoke matrix,
prioritizing personal Claude, worktrees and Git audit, Context7/Serena registration, the client
Claude Vertex plan and sandbox restarts. Record the CLI/daemon revision and results here.

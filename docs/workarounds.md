# Integration workaround register

`AGENTS.md` defines the architecture, `bin/check-sbx-version.py` enforces the SBX floor, and
`env/` records selected official digests. [Cutover evidence](cutover.md) records historical native
results. Keep this register with each adapter; do not infer that an upstream fix shipped from a
release number or from a successful run with the adapter enabled.

Retirement probes run in disposable compositions with just the named workaround removed. After
the probe succeeds, run `tests/validate.sh` and the affected environment's fresh, stop/start and
delete/recreate smoke before removing the workaround. Never use existing project VMs as probes.

| Adapter and owner | Evidence and scope | Removal condition and probe |
| --- | --- | --- |
| Thin Claude/OpenCode workloads, `workloads/claude-dev`, `workloads/opencode-dev` | Standalone workload names collided with SBX built-ins at the original 0.46 cutover. Current smoke validates the thin compositions; collision removal has not been demonstrated on the current supported release. Official agent mixins still own agent binaries/auth/provider policy. | Compose the corresponding pinned official standalone workload directly with `mixins/dev`; native plan, creation, agent `--help`, gateway/context/skills, arguments and full lifecycle smoke must pass. Preserve the profile's launch defaults when replacing the thin identity. |
| Antigravity config ancestor ownership, root install hook in `mixins/dev/dev.yaml` | Root-owned `.gemini` and `.gemini/config` prevented official configuration writes on 0.46. Retained pending a clean probe; passing later smoke with `chown` enabled is not proof of a continuing upstream defect. | Remove only `chown` in a disposable Antigravity composition. Both directories must be writable by `agent`, and official gateway/config hooks must pass on creation and restart with native skills enabled. |
| Malformed MCP protection, `mixins/dev/jq-guard.py` and `export-tools.py`; selection in `dev.yaml` | Pinned OpenCode/Antigravity hooks merge using jq, which can replace arrays/null. Guard resolves every argument to identify the two protected config files, checking root and MCP-map shapes before jq runs. It does not match specific options, filter text or operand positions. | Official hooks must reject malformed JSON, non-object roots and array/null MCP maps without replacing original bytes, while still merging valid settings. Run `check_gateway_merge_guard` via native smoke against the installed official startup hook with guard selection removed. Retire the exported guard only when the unmodified official hooks pass. |
| uv/uvx fallback, root install hook in `dev.yaml` | Some original official bases shipped binaries that aborted. Replacement is conditional on each workload binary's version probe failing. Shared baked tools remain the fallback. | With fallback removed, each selected workload's `uv --version`, `uvx --version` and a disposable `uv venv` operation must succeed; full tooling smoke must pass. Do not infer binary compatibility from executable presence. |
| Java proxy CA import, root install hook in `dev.yaml` | Shared Java has its own trust store. When SBX supplies `proxy-ca.crt`, the hook imports it once as `sbx-proxy`. This is sandbox proxy integration, separate from public CA maintenance. | Native SBX or the official Java tooling must provision trusted proxy roots without the hook. Verify keytool trust and a Java HTTPS request through the native proxy without manual import, plus Junie JVM MCP smoke. |
| OpenCode executable selection, `workloads/opencode-dev/opencode-dev.dockerfile` | The selected official mixin's wrapper referenced a missing extensionless executable; native PATH selects the same mixin's working npm executable. | A replacement official mixin must expose a working `opencode --help` with no local PATH override. Then pass default provider/argument behavior and lifecycle smoke. |
| Vendor domain grouping, developer network policy in `mixins/dev/dev.yaml` | The original full OpenCode composition exceeded the runtime's 4096-byte kit-lock label limit. Vendor wildcard rules reduced descriptor size while covering the listed hosts, with broader subdomain access. | A native metadata-capacity fix or smaller official composition must allow explicit required hosts without label errors. Restore narrower host rules in a disposable full OpenCode composition and verify creation, tool downloads and lifecycle smoke before retiring grouping. |
| Junie provider egress, `workloads/junie-dev` | The selected CLI used `ingrazzio-cloud-prod.labs.jb.gg`, absent from the official workload policy. | An official replacement must declare this backend (or its verified successor); remove the local domain and verify an authenticated backend request, distinguishing provider account/balance errors from policy or transport failures. |
| Junie gateway registration/JVM proxy, `mixins/dev/configure-agent.py` | Original official workload omitted gateway registration; Junie's JVM ignored HTTP_PROXY. Python gateway calls alone did not reveal the JVM failure. | Official kit must register the native gateway and its actual JVM client must connect without local registration or proxy adaptation. Native Junie smoke launches the actual interactive client and waits for successful gateway initialization. A Python HTTP probe alone is insufficient. |
| Junie public secret placeholder, `workloads/junie-dev/token-placeholder.py` and launcher integration | Official workload masked a native custom-secret placeholder with `proxy-managed`. Adapter selects public metadata only; native SBX stores/substitutes the host token. | Official workload must preserve a native injected placeholder and cover required provider domains. Remove adapter in a disposable authenticated Junie composition and complete a provider request; verify no token retrieval/copying was added. |

The jq guard deliberately covers invocations with protected file arguments, including aliases and
symlinks. A hook that reads configuration solely through stdin, invokes another jq binary or changes
the configuration location is outside that boundary. Native smoke reads staged official kit
descriptors and runs the actual gateway startup hook against malformed fixtures, restoring the
configuration afterward. An unrecognized hook fails the probe for review. Offline wrapper tests
cover option/filter/order/path changes; they cannot certify a newly published official descriptor.

The last recorded complete supported-release runtime matrix is in [cutover evidence](cutover.md).
New guard tests and a stronger installed-hook probe do not by themselves constitute a new native
runtime verification. Record that result only after the rebuilt mixin is exercised.

Junie's JVM proxy adaptation reads the native runtime `HTTP_PROXY`/`HTTPS_PROXY` values and updates
the official installed versions' jpackage configuration during install/startup. A self-update inside
an active session can install a new launcher configuration before the next reconciliation. After
such an update, stop the sandbox with `sbx stop <name>` and relaunch to reconcile the new version
before relying on MCP transport. Updates remain enabled.

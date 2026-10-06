# V3 cutover evidence

The repository now contains the V3 architecture from `CODEX_REWRITE_PROMPT.md`.
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

- SBX 0.46 creates Antigravity's skills ancestors as root-owned directories. A native root install
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
  The exported jq launcher validates only their exact merge command and two configuration paths.
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
stop/start and disappears after recreation. The current smoke checks runtime behavior at every stage,
but does not independently assert persistence of arbitrary sandbox-local state.

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

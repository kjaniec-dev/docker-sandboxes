# SBX 0.48 compatibility implementation plan

**Goal:** Migrate the repository's CLI contracts to Docker Sandboxes 0.48.0+.

**Architecture:** Keep native SBX lifecycle, official V3 kits and the shared dev mixin.
Change the existing flags and inventory parser; retain reviewed kit digests until
replacement kits pass native validation and runtime smoke on the supported release.

**Spec:** [Docker SBX 0.48 release notes](https://github.com/docker/sbx-releases/releases/tag/v0.48.0)
and the user's migration requirements.

## Tasks

- [x] Update `tests/test_behavior.py` to accept stable 0.48.0 and newer versions,
  reject 0.47.x and the 0.48.0 prerelease, and verify the launcher uses `--detach`.
  Run the changed tests before updating `bin/sbx-dev`.
- [x] Add CLI boundary tests running the real smoke script with direct-array
  inventories and a fake external SBX command that rejects removed flags.
  Cover all lifecycle stages, malformed/occupied inventories and removal checks.
  Observe failures, then update both parsers and use `--detach --force`.
- [x] Raise the version floor in `bin/sbx-dev`, `tests/validate.sh`, `AGENTS.md`
  and `README.md`; preserve interactive launcher plan approval. Share the JSON
  `client.version` check through `bin/check-sbx-version.py`.
- [x] Inspect latest Claude/Codex kit availability without changing host SBX.
  Update obsolete compatibility comments in both Claude profiles and Codex.
  Update digests only after successful supported native validation and smoke.
- [x] Run `tests/validate.sh --offline`, then `tests/validate.sh`.
  Record actual results and blockers in `docs/cutover.md`: 62 tests pass;
  native validation stops because the host remains on SBX 0.47.0.
- [x] After the host upgrade, verify actual 0.48 version JSON, native kit builds/plans
  and replacement Claude/Codex kit digests. On 2026-10-15, select official Claude 2.1.292
  and Codex 0.162.1; Codex's `latest` artifact requires an unsupported capability.
- [x] Follow the new kits' native context directories and remove the obsolete Codex
  instruction symlink. Preserve test workspaces when native removal is unconfirmed.
- [x] Run the final native matrix: six environments pass full lifecycle smoke;
  Claude and Codex pass model requests at all three stages. Per the user's follow-up,
  client Claude receives plan validation only. Full validation passes 71 tests,
  five kit inspections and seven plans. See `docs/cutover.md` for final evidence.

## Review focus

Version rejection must happen before sandbox creation. Smoke must reject invalid
or occupied inventories before assuming ownership. The post-removal inventory
must catch a sandbox that remains present. Do not infer runtime success from the
fake CLI tests or prior SBX 0.47 evidence. Do not change `SBX_AGENT_KIND` until
native `SBX_AGENT` values have been verified for all workload compositions.

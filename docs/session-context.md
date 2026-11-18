# Claude Code and Codex session context (SBX 0.54)

This feature complements opt-in localhost ports. It does not change port permissions.

## Claude Code

The shared dev kit installs `/opt/sbx-dev/claude-statusline.py` and configures
`~/.claude/settings.json` `statusLine` **only if the user has not already
configured a statusline**. Existing settings are preserved. The script reads
Claude's statusline JSON on stdin and prints the model, context-used percentage
and context-window size when those fields are available. It never sends data
to the host or to a network service.

It does **not** equate context occupancy with cumulative input/output tokens,
provider quotas, or cost. Unknown values are omitted rather than estimated.

## Codex

Use Codex's native session UI (for example `/status` where supported) to view
context usage and model/limit information. No undocumented session JSON parser
or cross-sandbox log scraper is installed. A future custom statusline should
only be added after the installed Codex version's supported API is confirmed.

## Manual checks (owner's Mac)

```bash
sbx version --json
python3 -m unittest discover -s tests -p 'test_claude_statusline.py'
./tests/validate.sh
SBX_PROFILE=personal ./tests/smoke.sh claude
SBX_PROFILE=personal ./tests/smoke.sh codex
SBX_AUTO_PORTS=1 SBX_PROFILE=personal ./tests/smoke.sh codex
```

Also run the remaining four personal/client agent smoke combinations from
`docs/upgrade-sbx-0.54.md`. In an actual Claude session verify that the
statusline updates as context grows and that existing custom statusLine
settings are not replaced. In Codex, verify the native status UI. For ports,
verify a disposable loopback publish/unpublish and that default profiles
remain unprivileged.

**Manual macOS smoke: PENDING / NOT RUN.** Record exact SBX and agent versions,
PR HEAD SHA, redacted evidence, PASS/FAIL/BLOCKED and cleanup result.

# Claude Code and Codex session context (SBX 0.54)

This feature complements opt-in localhost ports. It does not change port permissions.

## Claude Code

The shared dev kit installs `/opt/sbx-dev/claude-statusline.py` and configures
`~/.claude/settings.json` `statusLine` when no custom statusline is configured.
The known Narwhal-only hook is wrapped so it still receives its payload while
the terminal displays the model, current input-context tokens, context-window
size and percentage when available. Other custom statuslines are preserved.

It does **not** equate context occupancy with cumulative input/output tokens,
provider quotas, or cost. Unknown values are omitted rather than estimated.

## Codex

The shared dev kit configures Codex's native status line with the model, context
percentage, session tokens and context-window size when no custom status line
or provider is configured. Codex's session token count is cumulative, while
its context percentage describes the current window. `/statusline` can be used
to customize the display.

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

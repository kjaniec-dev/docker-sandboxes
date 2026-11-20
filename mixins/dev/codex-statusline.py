#!/usr/bin/env python3
"""Set the native Codex status line only when it is not already configured."""
import json
import os
from pathlib import Path
import re
import tempfile
import tomllib

ITEMS = ['model-with-reasoning', 'context-used', 'used-tokens', 'context-window-size']


def configure(original):
    data = tomllib.loads(original)
    tui = data.get('tui', {})
    if not isinstance(tui, dict) or 'status_line' in tui or 'status_line_provider' in tui:
        return original
    line = 'status_line = ' + json.dumps(ITEMS) + '\n'
    match = re.search(r'(?m)^\s*\[tui\]\s*(?:\#.*)?$', original)
    if match:
        updated = original[:match.end()] + '\n' + line + original[match.end():].lstrip('\n')
    elif 'tui' not in data:
        updated = original.rstrip() + '\n\n[tui]\n' + line
    else:
        return original
    expected = dict(data)
    expected['tui'] = {**tui, 'status_line': ITEMS}
    if tomllib.loads(updated) != expected:
        return original
    return updated


def main():
    path = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex') / 'config.toml'
    original = path.read_text() if path.exists() else ''
    updated = configure(original)
    if updated == original:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.config.toml.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(updated)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == '__main__':
    main()

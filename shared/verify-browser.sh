#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || exit 0
fi

playwright-cli --version
# Exercise the same Playwright installation used by the global CLI, without
# downloading packages or requiring access to an external website.
node - "$(npm root -g)/@playwright/cli/node_modules/playwright" <<'JS'
const { chromium } = require(process.argv[2]);

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent('<title>Sandbox browser check</title><button>OK</button>');
    await page.getByRole('button', { name: 'OK' }).click();
    if (await page.title() !== 'Sandbox browser check') {
      throw new Error('Unexpected browser page title');
    }
    console.log('Playwright Chromium verification passed');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
JS

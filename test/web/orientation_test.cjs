const {chromium} = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', args: ['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}});
    await page.setContent(fs.readFileSync('web/index.html', 'utf8').replace(/<script[^>]*><\/script>/g, ''));
    const guide = page.locator('#portrait-guide');
    assert.equal(await guide.isVisible(), false);
    // Reproduce a host whose size has not caught up with device rotation.
    await page.evaluate(() => document.querySelector('#app-host').style.height = '844px');
    for (let i = 0; i < 3; i++) {
      await page.setViewportSize({width: 844, height: 390});
      await guide.waitFor({state: 'visible'});
      assert.equal(await page.evaluate(() => document.elementFromPoint(400, 200).id), 'portrait-guide');
      await page.setViewportSize({width: 390, height: 844});
      await guide.waitFor({state: 'hidden'});
    }
    await page.evaluate(() => {
      const input = document.createElement('input');
      document.querySelector('#app-host').append(input);
      input.focus();
    });
    await page.setViewportSize({width: 390, height: 300});
    assert.equal(await guide.isVisible(), false);
    await page.locator('input').evaluate(input => input.blur());
    await guide.waitFor({state: 'visible'});
    console.log('Orientation checks passed: stale host, repeated rotation, keyboard editing.');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});

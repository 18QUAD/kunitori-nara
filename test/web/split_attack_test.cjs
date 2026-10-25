const {chromium} = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', args: ['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true});
    await page.setContent(fs.readFileSync('web/index.html', 'utf8').replace(/<script[^>]*><\/script>/g, ''));
    await page.evaluate(() => {
      window.taps = 0;
      const button = document.createElement('button');
      button.className = 'attack-tap-native';
      const style = 'position:absolute;left:12px;top:600px;width:366px;height:132px;visibility:visible;touch-action:manipulation';
      button.style.cssText = style;
      button.setAttribute('aria-label', 'タップで進軍 · 1人');
      button.addEventListener('pointerdown', () => window.taps++);
      button.addEventListener('click', event => {
        if (event.detail !== 0) return;
        window.taps++;
        // Flutter refreshes the full native style after game updates.
        button.style.cssText = style;
      });
      document.querySelector('#app-host').append(button);
    });
    await page.addScriptTag({content: fs.readFileSync('web/split_attack.js', 'utf8')});
    const left = page.locator('.attack-tap-native');
    const right = page.locator('.attack-tap-half');
    await right.waitFor({state: 'visible'});
    const a = await left.boundingBox(), b = await right.boundingBox();
    assert.equal(a.width, b.width);
    assert.equal(b.x - a.x - a.width, 8);
    assert.equal(b.x + b.width, 378);
    const cdp = await page.context().newCDPSession(page);
    const touch = (type, touchPoints) => cdp.send('Input.dispatchTouchEvent', {type, touchPoints});
    for (let i = 0; i < 5; i++) {
      await touch('touchStart', [{id: 1, x: 90, y: 660}, {id: 2, x: 285, y: 660}]);
      await touch('touchEnd', []);
      await page.waitForTimeout(50);
      assert.equal(await page.evaluate(() => taps), (i + 1) * 2, 'Two simultaneous fingers must count twice without compatibility-click duplicates');
    }
    await left.focus();
    await page.keyboard.press('Enter');
    await right.focus();
    await page.keyboard.press('Space');
    assert.equal(await page.evaluate(() => taps), 12);
    await left.evaluate(button => button.disabled = true);
    await page.waitForFunction(() => document.querySelector('.attack-tap-half').disabled);
    await touch('touchStart', [{id: 1, x: 90, y: 660}, {id: 2, x: 285, y: 660}]);
    await touch('touchEnd', []);
    assert.equal(await page.evaluate(() => taps), 12);
    await left.evaluate(button => button.disabled = false);
    await page.setViewportSize({width: 844, height: 390});
    assert.equal(await right.isVisible(), false);
    assert.equal((await left.boundingBox()).width, 366);
    await page.setViewportSize({width: 390, height: 844});
    await right.waitFor({state: 'visible'});
    await left.evaluate(button => button.style.visibility = 'hidden');
    await right.waitFor({state: 'hidden'});
    await left.evaluate(button => button.remove());
    await right.waitFor({state: 'detached'});
    console.log('Split attack checks passed: equal targets, simultaneous touch, no duplicate clicks, keyboard, disabled state, rotation, route visibility, cleanup.');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});

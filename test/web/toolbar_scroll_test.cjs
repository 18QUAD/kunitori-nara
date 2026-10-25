const {chromium} = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    args: ['--no-sandbox'],
  });
  try {
    const page = await browser.newPage({
      viewport: {width: 844, height: 390}, isMobile: true, hasTouch: true,
    });
    await page.setContent(fs.readFileSync('web/index.html', 'utf8').replace(/<script[^>]*><\/script>/g, ''));
    // Flutter owns gestures on its rendering surface. Native scroll must work
    // despite this, without taking the central map or bottom button gestures.
    await page.evaluate(() => {
      document.querySelector('#app-host').style.touchAction = 'none';
      const map = document.createElement('div');
      map.id = 'test-map';
      map.style.cssText = 'position:absolute;left:22%;width:56%;height:100%';
      const button = document.createElement('button');
      button.id = 'test-action';
      button.textContent = '進軍';
      button.style.cssText = 'position:absolute;left:12px;bottom:16px;width:150px;height:70px';
      button.onclick = () => button.dataset.clicked = 'yes';
      document.querySelector('#app-host').append(map, button);
    });
    const cdp = await page.context().newCDPSession(page);
    const swipe = async (x, from, to) => {
      await cdp.send('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{x, y: from}]});
      for (let i = 1; i <= 10; i++) {
        await cdp.send('Input.dispatchTouchEvent', {type: 'touchMove', touchPoints: [{x, y: from + (to - from) * i / 10}]});
        await page.waitForTimeout(20);
      }
      await cdp.send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
      await page.waitForTimeout(250);
    };
    for (const x of [60, 780]) {
      await page.evaluate(() => scrollTo(0, 0));
      await swipe(x, 220, 110);
      assert(await page.evaluate(() => scrollY > 0), 'Sidebar swipe must scroll the document');
      const host = await page.locator('#app-host').boundingBox();
      assert.equal(host.y, 0, 'Game must stay at the top while Safari scrolls');
      assert.equal(host.height, 390);
    }
    assert.equal(await page.evaluate(() => document.elementFromPoint(420, 180).id), 'test-map');
    await page.locator('#test-action').click();
    assert.equal(await page.locator('#test-action').getAttribute('data-clicked'), 'yes');
    await page.evaluate(() => {
      const dialog = document.createElement('div');
      dialog.setAttribute('role', 'dialog');
      document.body.append(dialog);
    });
    assert.equal(await page.locator('#browser-scroll-left').isVisible(), false, 'Dialog must retain its gestures');
    await page.locator('[role=dialog]').evaluate(dialog => dialog.remove());
    await page.setViewportSize({width: 390, height: 844});
    assert.equal(await page.locator('#browser-scroll-left').isVisible(), false);
    assert.equal(await page.evaluate(() => scrollY), 0);
    console.log('Toolbar scroll checks passed: native touch scroll on both sides, stationary game, map gestures, action button, portrait rotation.');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});

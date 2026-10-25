const {chromium} = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', args: ['--no-sandbox']});
  try {
    const page = await browser.newPage({viewport: {width: 844, height: 390}, isMobile: true, hasTouch: true});
    await page.setContent(fs.readFileSync('web/index.html', 'utf8').replace(/<script[^>]*><\/script>/g, ''));
    await page.evaluate(() => {
      window.taps = [0, 0];
      for (let side = 0; side < 2; side++) {
        const button = document.createElement('button');
        button.className = 'attack-tap-native';
        const style = `position:absolute;left:${side ? 652 : 12}px;top:240px;width:180px;height:132px;visibility:visible;touch-action:manipulation`;
        button.style.cssText = style;
        // Model the old contact gate and its programmatic/keyboard fallback.
        button.addEventListener('pointerdown', event => {if (event.isPrimary) window.taps[side]++;});
        button.addEventListener('click', event => {
          if (event.detail === 0 && !event.pointerType) {
            window.taps[side]++;
            button.style.cssText = style;
          }
        });
        document.querySelector('#app-host').append(button);
      }
    });
    await page.addScriptTag({content: fs.readFileSync('web/split_attack.js', 'utf8')});
    await page.waitForFunction(() => document.querySelectorAll('.attack-tap-native[data-split-ready]').length === 2);
    const zoomGuard = await page.evaluate(() => {
      const button = document.querySelector('.attack-tap-native');
      const makeTouch = (target, identifier) => new Touch({identifier, target, clientX: 90, clientY: 300});
      const fireTouch = (type, target, touch) => {
        const event = new TouchEvent(type, {bubbles: true, cancelable: true, changedTouches: [touch]});
        target.dispatchEvent(event);
        return event.defaultPrevented;
      };
      const gesture = target => {
        const event = new Event('gesturestart', {bubbles: true, cancelable: true});
        target.dispatchEvent(event);
        return event.defaultPrevented;
      };
      const contact = makeTouch(button, 99);
      const start = fireTouch('touchstart', button, contact);
      const crossButtonGesture = gesture(document.querySelector('#app-host'));
      const move = fireTouch('touchmove', button, contact);
      fireTouch('touchcancel', button, contact);
      const afterCancel = gesture(document.querySelector('#app-host'));
      const rail = document.querySelector('#browser-scroll-left');
      const scroll = fireTouch('touchstart', rail, makeTouch(rail, 100));
      const map = document.createElement('div');
      document.querySelector('#app-host').append(map);
      const mapTouch = fireTouch('touchstart', map, makeTouch(map, 101));
      return {start, move, crossButtonGesture, afterCancel, scroll, mapTouch, action: getComputedStyle(button).touchAction};
    });
    assert.deepEqual(zoomGuard, {start: true, move: true, crossButtonGesture: true, afterCancel: false, scroll: false, mapTouch: false, action: 'none'});
    const cdp = await page.context().newCDPSession(page);
    const touch = (type, touchPoints) => cdp.send('Input.dispatchTouchEvent', {type, touchPoints});
    const left = {id: 1, x: 90, y: 300}, right = {id: 2, x: 750, y: 300};
    for (let i = 1; i <= 10; i++) {
      await touch('touchStart', [left, right]);
      await touch('touchEnd', []);
      assert.deepEqual(await page.evaluate(() => taps), [i, i], 'Each simultaneous contact must count once on its own side');
    }
    // Keep one finger down while repeatedly adding/removing the other.
    await touch('touchStart', [left]);
    for (let i = 0; i < 3; i++) {
      await touch('touchStart', [left, right]);
      await touch('touchEnd', [right]);
    }
    await touch('touchCancel', []);
    assert.deepEqual(await page.evaluate(() => taps), [11, 13]);
    await touch('touchStart', [left, right]);
    await touch('touchEnd', []);
    assert.deepEqual(await page.evaluate(() => taps), [12, 14], 'Canceled contacts must not block the next sequence');
    await page.locator('.attack-tap-native').first().evaluate(button => button.disabled = true);
    await touch('touchStart', [left, right]);
    await touch('touchEnd', []);
    assert.deepEqual(await page.evaluate(() => taps), [12, 15]);
    await page.locator('.attack-tap-native').nth(1).focus();
    await page.keyboard.press('Enter');
    assert.deepEqual(await page.evaluate(() => taps), [12, 16]);
    await page.locator('.attack-tap-native').first().evaluate(button => button.disabled = false);
    await touch('touchStart', [left, right]);
    for (let step = 1; step <= 10; step++) {
      await touch('touchMove', [{...left, x: left.x - step * 2}, {...right, x: right.x + step * 2}]);
    }
    await touch('touchEnd', []);
    assert.equal(await page.evaluate(() => visualViewport.scale), 1, 'A cross-button pinch must not zoom the browser');
    assert.deepEqual(await page.evaluate(() => taps), [13, 17]);
    console.log('Landscape attack checks passed: repeated simultaneous taps, held contact, cancellation recovery, disabled side, keyboard, no duplicate clicks, scoped touch and Safari gesture defaults, cross-button pinch.');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});

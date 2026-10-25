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
    const bridge = page.locator('.attack-tap-native');
    const left = page.locator('.attack-tap-half[data-side=left]');
    const right = page.locator('.attack-tap-half[data-side=right]');
    await right.waitFor({state: 'visible'});
    assert.equal(await bridge.evaluate(button => getComputedStyle(button).opacity), '0');
    const a = await left.boundingBox(), b = await right.boundingBox();
    assert.equal(a.width, b.width);
    assert.equal(b.x - a.x - a.width, 8);
    assert.equal(b.x + b.width, 378);
    async function effectOn(selector) {
      return page.evaluate(async selector => {
        document.querySelector(selector).dispatchEvent(new PointerEvent('pointerdown', {button: 0, bubbles: true}));
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return [...document.querySelectorAll('.attack-tap-native, .attack-tap-half')].map(button => ({
          active: button.getAnimations().some(animation => animation.playState === 'running'),
          highlight: getComputedStyle(button).webkitTapHighlightColor,
        }));
      }, selector);
    }
    await page.evaluate(() => {
      window.leftStyleChanges = 0;
      new MutationObserver(records => window.leftStyleChanges += records.length)
        .observe(document.querySelector('.attack-tap-half[data-side=left]'), {attributes: true, attributeFilter: ['style']});
    });
    let effects = await effectOn('.attack-tap-half[data-side=right]');
    assert.deepEqual(effects.map(effect => effect.active), [false, false, true], 'Right press must not animate the left button, even after Flutter refreshes styles');
    assert.equal(await page.evaluate(() => leftStyleChanges), 0, 'Right tap must not rewrite the left display target style');
    assert(effects.every(effect => effect.highlight === 'rgba(0, 0, 0, 0)'));
    await page.waitForTimeout(180);
    effects = await effectOn('.attack-tap-half[data-side=left]');
    assert.deepEqual(effects.map(effect => effect.active), [false, true, false], 'Left press must not animate the right button');
    await page.waitForTimeout(180);
    assert.equal(await page.evaluate(() => taps), 2);
    const cdp = await page.context().newCDPSession(page);
    const touch = (type, touchPoints) => cdp.send('Input.dispatchTouchEvent', {type, touchPoints});
    for (let i = 0; i < 5; i++) {
      await touch('touchStart', [{id: 1, x: 90, y: 660}, {id: 2, x: 285, y: 660}]);
      await touch('touchEnd', []);
      await page.waitForTimeout(50);
      assert.equal(await page.evaluate(() => taps), (i + 1) * 2 + 2, 'Two simultaneous fingers must count twice without compatibility-click duplicates');
    }
    await left.focus();
    await page.keyboard.press('Enter');
    await right.focus();
    await page.keyboard.press('Space');
    assert.equal(await page.evaluate(() => taps), 14);
    await bridge.evaluate(button => button.disabled = true);
    await page.waitForFunction(() => [...document.querySelectorAll('.attack-tap-half')].every(button => button.disabled));
    await touch('touchStart', [{id: 1, x: 90, y: 660}, {id: 2, x: 285, y: 660}]);
    await touch('touchEnd', []);
    assert.equal(await page.evaluate(() => taps), 14);
    await bridge.evaluate(button => button.disabled = false);
    await page.setViewportSize({width: 844, height: 390});
    assert.equal(await right.isVisible(), false);
    assert.equal((await bridge.boundingBox()).width, 366);
    assert.equal(await bridge.evaluate(button => getComputedStyle(button).opacity), '1');
    await page.setViewportSize({width: 390, height: 844});
    await right.waitFor({state: 'visible'});
    await bridge.evaluate(button => button.style.visibility = 'hidden');
    await right.waitFor({state: 'hidden'});
    await bridge.evaluate(button => button.remove());
    await right.waitFor({state: 'detached'});
    console.log('Split attack checks passed: equal targets, independent press effects, simultaneous touch, no duplicate clicks, keyboard, disabled state, rotation, route visibility, cleanup.');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});

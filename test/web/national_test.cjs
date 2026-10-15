// BASE_URL must serve the release build at its /kunitori-nara/ base path.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
let browser;

(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.SCREENSHOT_DIR || '/tmp/kunitori-national-screenshots';
  fs.mkdirSync(output, {recursive: true});
  browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    proxy: process.env.HTTPS_PROXY ? {server: process.env.HTTPS_PROXY, bypass: '127.0.0.1,localhost'} : undefined,
    args: ['--no-sandbox'],
  });
  const page = await browser.newPage({viewport: {width: 390, height: 844}, isMobile: true, hasTouch: true, deviceScaleFactor: Number(process.env.DEVICE_SCALE_FACTOR || 1)});
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const key = 'flutter.kunitori.nara.v1';
  const mapKey = 'flutter.kunitori.nara.mapView.v1';
  const fixture = {
    version: 1, quizRule: 'office-five-v1', dataset: 'nara-2020-v1',
    tapRule: 'population-v1', territoryUnit: 'town-v1', difficulty: 'standard',
    home: '29205043001', attackTarget: '29205041001',
    owned: ['29205043001'], everOwned: ['29205043001'],
    titles: ['大和への第一歩'], mastered: [], seen: ['29205:count'],
    progress: {'29205041001': 7}, totalTaps: 7, cityTaps: {'29205': 7},
    cityTapsComplete: true, wins: 4, losses: 3, quiz: null,
  };
  await page.addInitScript(({key, fixture}) => {
    if (!localStorage.getItem(key)) localStorage.setItem(key, JSON.stringify(JSON.stringify(fixture)));
  }, {key, fixture});
  // External optional map/advertising services do not affect these offline checks.
  await page.route('https://**', route => new URL(route.request().url()).origin === new URL(base).origin ? route.continue() : route.abort());
  async function toNational() {
    const before = await view();
    await page.getByRole('button', {name: '1段上の地図を表示', exact: true}).click();
    if (before.cityId != null) {
      await page.waitForFunction(key => JSON.parse(JSON.parse(localStorage.getItem(key))).cityId == null, mapKey);
      assert.equal((await view()).nationalView, false, 'A municipality must first return to its prefecture');
      await page.getByRole('button', {name: '1段上の地図を表示', exact: true}).click();
    }
    await page.waitForFunction(key => JSON.parse(JSON.parse(localStorage.getItem(key))).nationalView, mapKey);
  }
  const game = () => page.evaluate(key => JSON.parse(JSON.parse(localStorage.getItem(key))), key);
  const view = () => page.evaluate(key => JSON.parse(JSON.parse(localStorage.getItem(key))), mapKey);
  async function semantics() {
    await page.locator('flutter-view').waitFor({state: 'attached', timeout: 120000});
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.evaluate(e => e.click());
  }
  await page.goto(base, {waitUntil: 'networkidle'});
  await semantics();
  const attack = page.getByRole('button', {name: 'タップで進軍 · 1人', exact: true});
  await attack.waitFor({timeout: 120000});
  assert.deepEqual((await game()).progress, fixture.progress);
  await page.getByLabel('背景地図の読込完了', {exact: true}).waitFor({timeout: 30000});
  const tilesBeforeTap = await page.evaluate(() => performance.getEntriesByType('resource').filter(e => e.name.includes('/map_tiles_uniform/')).length);
  await attack.tap();
  await page.waitForFunction(key => JSON.parse(JSON.parse(localStorage.getItem(key))).totalTaps === 8, key);
  await page.waitForTimeout(200);
  assert.equal(await page.evaluate(() => performance.getEntriesByType('resource').filter(e => e.name.includes('/map_tiles_uniform/')).length), tilesBeforeTap);
  assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /map_tiles_uniform\/[56]_/.test(e.name))), 'Nara must use the shared fine water-stroke tiles');
  assert(!(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /\/map_tiles\//.test(e.name)))), 'Current build must not load legacy tiles');
  await page.screenshot({path: path.join(output, 'nara-saved-campaign.png')});
  await toNational();
  await page.waitForFunction(() => performance.getEntriesByType('resource').some(e => /map_tiles_uniform\/.*_overview\.webp/.test(e.name)));
  const map = page.getByLabel('全国地図', {exact: true});
  await map.waitFor();
  await page.waitForFunction(key => JSON.parse(JSON.parse(localStorage.getItem(key))).nationalView, mapKey);
  await page.getByText('起伏を読み込み中…', {exact: true}).waitFor({state: 'hidden', timeout: 120000});
  await page.getByLabel('背景地図の読込完了', {exact: true}).waitFor({timeout: 30000});
  assert.equal(await page.getByText('起伏を読み込めませんでした · 再試行', {exact: true}).count(), 0);
  assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /map_tiles_uniform\/.*_shade\.webp/.test(e.name))));
  await page.getByText('市街地を読み込み中…', {exact: true}).waitFor({state: 'hidden', timeout: 120000});
  assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /map_tiles_uniform\/.*_detail\.webp/.test(e.name))));
  assert.equal(await page.getByText('市街地を読み込めませんでした · 再試行', {exact: true}).count(), 0);
  await page.getByText('川・湖を読み込み中…', {exact: true}).waitFor({state: 'hidden', timeout: 120000});
  assert.equal(await page.getByText('川・湖を読み込めませんでした · 再試行', {exact: true}).count(), 0);
  assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => e.name.includes('map_labels/national.json'))));
  const nationalCamera = await view();
  await page.getByRole('button', {name: '起伏・市街地・川・池・湖を非表示', exact: true}).click();
  await page.waitForFunction(key => !JSON.parse(JSON.parse(localStorage.getItem(key))).showGeography, mapKey);
  assert.deepEqual((await view()).center, nationalCamera.center);
  await page.reload({waitUntil: 'networkidle'});
  await semantics();
  await page.getByRole('button', {name: '起伏・市街地・川・池・湖を表示', exact: true}).waitFor({timeout: 120000});
  assert.equal((await view()).nationalView, true);
  await page.getByRole('button', {name: '起伏・市街地・川・池・湖を表示', exact: true}).click();
  await page.waitForFunction(key => JSON.parse(JSON.parse(localStorage.getItem(key))).showGeography, mapKey);
  const before = await view();
  await page.getByRole('button', {name: '拡大', exact: true}).click();
  await page.waitForFunction(({key, scale}) => JSON.parse(JSON.parse(localStorage.getItem(key))).scale > scale, {key: mapKey, scale: before.scale});
  await page.screenshot({path: path.join(output, 'national-urban-zoom.png')});
  for (var i = 0; i < 4; i++) { await page.getByRole('button', {name: '拡大', exact: true}).click(); console.log('National zoom step', i + 2); }
  await page.waitForFunction(() => performance.getEntriesByType('resource').some(e => /map_tiles_uniform\/[1-4]_/.test(e.name)));
  await page.getByLabel('背景地図の読込完了', {exact: true}).waitFor({timeout: 30000});
  await page.screenshot({path: path.join(output, 'national-image-LOD.png')});
  for (var i = 0; i < 5; i++) await page.getByRole('button', {name: '縮小', exact: true}).click();
  await page.getByLabel('背景地図の読込完了', {exact: true}).waitFor({timeout: 30000});
  await page.screenshot({path: path.join(output, 'national-prefecture-borders.png')});
  const prefectureStart = Date.now();
  await page.getByRole('button', {name: '北海道', exact: true}).click();
  await page.getByRole('button', {name: '1段上の地図を表示', exact: true}).waitFor({timeout: 120000});
  await page.waitForFunction(key => {const v = JSON.parse(JSON.parse(localStorage.getItem(key))); return v.prefectureId === '01' && !v.nationalView;}, mapKey);
  console.log('Hokkaido map ready in', Date.now() - prefectureStart, 'ms');
  const pending = 'この地域の歴史・文化tipsは準備中です。';
  await page.getByText(pending, {exact: true}).or(page.getByLabel(pending, {exact: true})).first().waitFor();
  const terrain = page.getByRole('button', {name: '起伏・市街地・川・池・湖を非表示', exact: true});
  await terrain.waitFor();
  await page.waitForFunction(() => performance.getEntriesByType('resource').some(e => /map_tiles_uniform\/.*_shade\.webp/.test(e.name)));
  await page.getByText('起伏を読み込み中…', {exact: true}).waitFor({state: 'hidden', timeout: 120000});
  assert.equal(await page.getByText('起伏を読み込めませんでした', {exact: true}).count(), 0);
  await page.getByText('市街地を読み込み中…', {exact: true}).waitFor({state: 'hidden', timeout: 120000});
  assert.equal(await page.getByText('市街地を読み込めませんでした', {exact: true}).count(), 0);
  assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /map_tiles_uniform\/.*_detail\.webp/.test(e.name))));
  await page.getByText('川・湖を読み込み中…', {exact: true}).waitFor({state: 'hidden', timeout: 120000});
  assert.equal(await page.getByText('川・湖を読み込めませんでした', {exact: true}).count(), 0);
  assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => e.name.includes('map_labels/01.json'))));
  await page.getByLabel('背景地図の読込完了', {exact: true}).waitFor({timeout: 30000});
  assert(!(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /\/(water|relief|urban)\//.test(e.name)))));
  console.log('Hokkaido terrain, urban and water ready in', Date.now() - prefectureStart, 'ms');
  await terrain.click();
  await page.waitForFunction(key => !JSON.parse(JSON.parse(localStorage.getItem(key))).showGeography, mapKey);
  await page.getByRole('button', {name: '起伏・市街地・川・池・湖を表示', exact: true}).click();
  await page.waitForFunction(key => JSON.parse(JSON.parse(localStorage.getItem(key))).showGeography, mapKey);
  await page.screenshot({path: path.join(output, 'hokkaido-placeholder-tips.png')});
  await page.getByRole('button', {name: '設定', exact: true}).click();
  await page.getByText('地名から探す', {exact: true}).click();
  const search = page.getByRole('textbox');
  await search.waitFor();
  // Wait for the sheet transition before sending input to Flutter's editor.
  await page.waitForTimeout(350);
  await search.fill('沖縄県');
  await page.screenshot({path: path.join(output, 'search-prefecture.png')});
  await page.getByText(/那覇市/).or(page.getByRole('button', {name: /那覇市/})).first().click({timeout:120000});
  await search.fill('首里');
  await page.screenshot({path: path.join(output, 'national-search.png')});
  await page.getByRole('button', {name: '閉じる', exact: true}).click();
  await toNational();
  await page.getByRole('button', {name: '攻略中の町へ', exact: true}).click();
  await attack.waitFor({timeout: 120000});
  await page.waitForFunction(key => !JSON.parse(JSON.parse(localStorage.getItem(key))).nationalView, mapKey);
  await page.reload({waitUntil: 'networkidle'});
  await semantics();
  await attack.waitFor({timeout: 120000});
  const restored = await game();
  assert.equal(restored.totalTaps, 8);
  assert.equal(restored.progress['29205041001'], 8);
  for (const field of ['home', 'owned', 'everOwned', 'titles', 'wins', 'losses']) assert.deepEqual(restored[field], fixture[field]);
  assert(restored.seen.includes('29205:count'));
  await toNational();
  await map.waitFor();
  await page.setViewportSize({width: 844, height: 390});
  await page.getByText('端末を縦向きにしてご利用ください', {exact: true}).waitFor();
  await page.screenshot({path: path.join(output, 'national-landscape-guard.png')});
  assert.deepEqual(errors, []);
  console.log('National release browser checks passed: saved campaign, taps, prefecture selection, zoom, placeholder tips, terrain, urban and water controls, search, home, reload, landscape guard.');
  await browser.close();
})().catch(async error => {console.error(error); await browser?.close(); process.exitCode = 1;});

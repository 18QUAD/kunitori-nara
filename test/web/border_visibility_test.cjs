// Compare the same Nara-area national camera at iPhone SE screen dimensions.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
let browser;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.SCREENSHOT || '/workspace/borders-plain-after.png';
  const scale = Number(process.env.MAP_SCALE || 8);
  const longitude = Number(process.env.CENTER_LON || 135.8);
  const latitude = Number(process.env.CENTER_LAT || 34.62);
  const nara = JSON.parse(fs.readFileSync(path.join(__dirname, '../../assets/data/nara.json')));
  const owned = nara.towns.filter(t => t.cityId === '29204').map(t => t.id);
  const game = {version: 1, quizRule: 'office-five-v1', dataset: 'nara-2020-v1',
    tapRule: 'population-v1', territoryUnit: 'town-v1', difficulty: 'standard',
    home: owned[0], attackTarget: null, owned, everOwned: owned, titles: [],
    mastered: [], seen: [], progress: {}, totalTaps: 160501,
    cityTaps: {'29204': 160501}, cityTapsComplete: true, wins: 0, losses: 0, quiz: null};
  const view = {dataset: 'nara-2020-v1', projection: '1100x1500-v1',
    center: [40 + (longitude - 122) * 42, 40 + (46 - latitude) * 50], scale,
    selected: null, cityId: null, prefectureId: '29', nationalView: true, showGeography: true};
  browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    proxy: process.env.HTTPS_PROXY ? {server: process.env.HTTPS_PROXY, bypass: '127.0.0.1,localhost'} : undefined,
    args: ['--no-sandbox']});
  const page = await browser.newPage({viewport: {width: 375, height: 667}, deviceScaleFactor: 2, isMobile: true, hasTouch: true});
  await page.addInitScript(({game, view}) => {
    performance.setResourceTimingBufferSize(5000);
    localStorage.setItem('flutter.kunitori.nara.v1', JSON.stringify(JSON.stringify(game)));
    localStorage.setItem('flutter.kunitori.nara.mapView.v1', JSON.stringify(JSON.stringify(view)));
  }, {game, view});
  await page.route('https://**', r => new URL(r.request().url()).origin === new URL(base).origin ? r.continue() : r.abort());
  await page.goto(base, {waitUntil: 'networkidle'});
  await page.locator('flt-semantics-placeholder').waitFor({state: 'attached', timeout: 120000});
  await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
  for (const label of ['境界線画像の読込完了', '背景地図の読込完了']) {
    await page.getByLabel(label, {exact: true}).or(page.getByText(label, {exact: true})).first().waitFor({timeout: 120000});
  }
  const saved = await page.evaluate(() => JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.mapView.v1'))));
  assert.equal(saved.scale, 128 * 2**Math.max(-3,Math.min(5,Math.round(Math.log2(scale*100/128)))) / 100);
  assert.equal(saved.nationalView, true);
  if (process.env.EXPECT_PLAIN !== '0') {
    assert(!(await page.evaluate(() => performance.getEntriesByType('resource').some(e => e.name.includes('prefecture_border_mesh.bin')))));
    assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /map_images\/index\.json/.test(e.name))));
    assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /map_images\/.*_pref\.webp/.test(e.name))));
  }
  // CanvasKit may finish late icon-font frames after the tile status is ready.
  await page.waitForTimeout(1500);
  await page.screenshot({path: output});
  await page.screenshot({path: output.replace('.png', '-map.png'), clip: {x: 0, y: 88, width: 375, height: 300}});
  console.log('PASS: national camera scale', scale, 'center', longitude, latitude, '; screenshot:', output);
  await browser.close();
})().catch(async e => {console.error(e); await browser?.close(); process.exitCode = 1;});

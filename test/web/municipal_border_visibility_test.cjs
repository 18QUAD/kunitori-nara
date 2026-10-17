// Reproduce the reported deep zoom in Nabari on an iPhone SE-sized viewport.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
let browser;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.SCREENSHOT || '/workspace/nabari-borders-after.png';
  const scale = Number(process.env.MAP_SCALE || 24);
  const geo = JSON.parse(fs.readFileSync(path.join(__dirname, '../../assets/data/prefectures/24.json')));
  const pts = geo.towns.flatMap(t => t.polygons.flat(2));
  const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
  const minX = xs.reduce((a,b)=>Math.min(a,b),Infinity), maxX = xs.reduce((a,b)=>Math.max(a,b),-Infinity), minY = ys.reduce((a,b)=>Math.min(a,b),Infinity), maxY = ys.reduce((a,b)=>Math.max(a,b),-Infinity);
  const ppd = Math.min(1020 / ((maxX-minX)*.826),1420/(maxY-minY));
  const dx=(1100-(maxX-minX)*.826*ppd)/2,dy=(1500-(maxY-minY)*ppd)/2;
  const townId = process.env.TOWN_ID || '242080950';
  const town=geo.towns.find(t=>t.id===townId);
  const homeId = townId === '242081650' ? '242081210' : '242080940';
  const ring=town.polygons[0][0];
  const lon=ring.reduce((a,p)=>a+p[0],0)/ring.length,lat=ring.reduce((a,p)=>a+p[1],0)/ring.length;
  const game = {version: 1, quizRule: 'office-five-v1', dataset: 'nara-2020-v1',
    tapRule: 'population-v1', territoryUnit: 'town-v1', difficulty: 'standard',
    home: homeId, attackTarget: townId, owned: [homeId], everOwned: [homeId], titles: [],
    mastered: [], seen: [], progress: {[townId]:37}, totalTaps: 160501,
    cityTaps: {'24208': 484}, cityTapsComplete: true, wins: 0, losses: 0, quiz: null};
  const view = {dataset: 'nara-2020-v1', projection: '1100x1500-v1',
    center: [dx+(lon-minX)*.826*ppd, dy+(maxY-lat)*ppd], scale,
    selected: townId, cityId: '24208', prefectureId: '24', nationalView: false, showGeography: true};
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
  assert.equal(saved.scale, scale);
  assert.equal(saved.nationalView, false);
  if (process.env.EXPECT_PLAIN !== '0') {
    assert(!(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /border_tiles\/.*_town\.webp/.test(e.name)))), 'Deep municipal zoom must use sharp cached images instead of enlarged offline tiles');
    assert(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /border_tiles\/index-slim\.json/.test(e.name))));
    assert(!(await page.evaluate(() => performance.getEntriesByType('resource').some(e => /border_tiles\/\d_/.test(e.name)))));
  }
  // CanvasKit may finish late icon-font frames after the tile status is ready.
  await page.waitForTimeout(1500);
  await page.screenshot({path: output});
  await page.screenshot({path: output.replace('.png', '-map.png'), clip: {x: 0, y: 88, width: 375, height: 300}});
  const townRequests = () => page.evaluate(() => performance.getEntriesByType('resource').filter(e => /border_tiles\/.*_town\.webp/.test(e.name)).length);
  const before = await townRequests();
  await page.evaluate(() => {
    window.zoomLockSeen = false;
    window.homeLockSeen = false;
    new MutationObserver(() => {
      const home = [...document.querySelectorAll('[role="button"]')].find(e =>
        ['本拠地へ', '攻略中の町へ'].includes(e.getAttribute('aria-label')));
      if (home?.getAttribute('aria-disabled') === 'true') window.homeLockSeen = true;
      if ([...document.querySelectorAll('[role="button"]')].some(e =>
        ['拡大', '縮小'].includes(e.getAttribute('aria-label')) && e.getAttribute('aria-disabled') === 'true')) {
        window.zoomLockSeen = true;
      }
    }).observe(document.body, {subtree: true, attributes: true, attributeFilter: ['aria-disabled']});
  });
  for (const control of ['拡大', '縮小']) {
    await page.getByRole('button', {name: control, exact: true}).click();
    await page.waitForTimeout(300);
    await page.getByLabel('境界線画像の読込完了', {exact: true}).or(page.getByText('境界線画像の読込完了', {exact: true})).first().waitFor({timeout: 30000});
    assert.equal(await townRequests(), before, 'Zoom must not enlarge offline town images');
  }
  assert(await page.evaluate(() => window.zoomLockSeen), 'Zoom buttons must disable during image work');
  assert(await page.evaluate(() => window.homeLockSeen), 'Home button must disable during image work');
  assert(await page.getByRole('button', {name: '攻略中の町へ', exact: true}).isEnabled(), 'Home must re-enable after image work');
  console.log('PASS: Nabari municipal camera scale', scale, 'center', lon, lat, '; screenshot:', output);
  await browser.close();
})().catch(async e => {console.error(e); await browser?.close(); process.exitCode = 1;});

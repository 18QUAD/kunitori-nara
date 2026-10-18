// Verify nationwide advertisements in the existing tips bubble on an iPhone SE-sized viewport.
// API responses are mocked here; the deployment workflow checks the live Worker.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
let browser;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.SCREENSHOT || '/workspace/nationwide-ads-card.png';
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
  const requests = [];
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.hostname === 'kunitori-nara-regional-ads.narusaki-masafumi.workers.dev' && url.pathname === '/ads') {
      const city = url.searchParams.get('city');
      requests.push(city);
      return route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({cityId:city,expiresAt:new Date(Date.now()+1800000).toISOString(),ads:[{cityId:city,category:'furusato',name:'表示検証用の返礼品',advertiser:'三重県名張市',url:'https://hb.afl.rakuten.co.jp/hgc/test/'}]})});
    }
    return url.origin === new URL(base).origin ? route.continue() : route.abort();
  });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(base,{waitUntil:'networkidle'});
  await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:120000});
  await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
  console.log('App loaded; waiting for advertisement');
  try {
    await page.getByRole('button',{name:/広告、名張市のふるさと納税、.*楽天市場で詳細を見る/}).waitFor({timeout:60000});
  } catch(error) {
    await page.screenshot({path:output.replace('.png','-failure.png')});
    console.error('Requested cities:',JSON.stringify(requests));
    console.error((await page.locator('body').innerText()).slice(-4000));
    throw error;
  }
  assert.deepEqual(requests,['24208']);
  await page.screenshot({path:output});
  const key='flutter.kunitori.nara.v1';
  const saved=await page.evaluate(key=>JSON.parse(JSON.parse(localStorage.getItem(key))),key);
  assert.equal(saved.totalTaps,game.totalTaps);
  assert.deepEqual(saved.progress,game.progress);
  assert.equal(saved.home,game.home);
  await page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click();
  await page.waitForFunction(()=>performance.getEntriesByType('resource').some(e=>e.name.includes('city=24201')));
  assert.deepEqual(requests,['24208','24201']);
  assert.deepEqual(errors,[]);
  console.log('PASS: non-Nara hometown tax ad appears in the existing tips bubble; visible prefecture determines requests; campaign unchanged.');
  await browser.close();
})().catch(async error=>{console.error(error);await browser?.close();process.exitCode=1;});

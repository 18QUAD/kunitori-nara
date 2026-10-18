// Stress a loaded map under a 512 MiB JS heap limit; record JS, WASM and renderer memory.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
let browser;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.MEMORY_OUTPUT || '/workspace/map-idle-memory.json';
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
    args: ['--no-sandbox','--js-flags=--max-old-space-size=512']});
  const page = await browser.newPage({viewport: {width: 375, height: 667}, deviceScaleFactor: 2, isMobile: true, hasTouch: true});
  await page.addInitScript(({game, view}) => {
    performance.setResourceTimingBufferSize(5000);
    localStorage.setItem('flutter.kunitori.nara.v1', JSON.stringify(JSON.stringify(game)));
    localStorage.setItem('flutter.kunitori.nara.mapView.v1', JSON.stringify(JSON.stringify(view)));
  }, {game, view});
  await page.route('**/*',r=>new URL(r.request().url()).origin===new URL(base).origin?r.continue():r.abort());
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('crash',()=>errors.push('Renderer crashed'));
  let documentLoads=0;page.on('load',()=>documentLoads++);
  await page.goto(base,{waitUntil:'networkidle'});
  await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:120000});
  await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
  for(const label of ['背景地図の読込完了','境界線画像の読込完了']) await page.getByLabel(label,{exact:true}).or(page.getByText(label,{exact:true})).first().waitFor({timeout:120000});
  const started=await page.evaluate(()=>performance.timeOrigin);
  const cdp=await page.context().newCDPSession(page);await cdp.send('Performance.enable');
  const processSession=await browser.newBrowserCDPSession();
  const samples=[];
  async function sample(stage){
    await cdp.send('HeapProfiler.collectGarbage');
    const metrics=await cdp.send('Performance.getMetrics');
    const heap=metrics.metrics.find(m=>m.name==='JSHeapUsedSize').value;
    const wasm=await page.evaluate(()=>window.flutterCanvasKit?.HEAPU8?.buffer.byteLength || 0);
    const info=await processSession.send('SystemInfo.getProcessInfo');
    let rss=0;
    for(const proc of info.processInfo.filter(p=>p.type==='renderer')){
      try{rss+=Number(fs.readFileSync(`/proc/${proc.id}/status`,'utf8').match(/VmRSS:\s+(\d+)/)[1])*1024;}catch{}
    }
    samples.push({stage,heap,wasm,rss});console.log(stage,JSON.stringify(samples.at(-1)));
  }
  await sample('loaded');
  await page.waitForTimeout(15000);await sample('idle');
  const attack=page.getByRole('button',{name:'タップで進軍 · 1人',exact:true});
  await attack.evaluate(async () => {for(let i=0;i<100;i++){document.querySelector('button.attack-tap-native').click();await new Promise(requestAnimationFrame);}});
  await page.waitForTimeout(300);await sample('100 taps');
  for(let i=0;i<2;i++){
    await page.getByRole('button',{name:'拡大',exact:true}).click();
    await page.getByRole('button',{name:'縮小',exact:true}).click();
    for(const label of ['背景地図の読込完了','境界線画像の読込完了'])await page.getByLabel(label,{exact:true}).or(page.getByText(label,{exact:true})).first().waitFor({timeout:120000});
    await sample('zoom cycle '+i);
  }
  const saved=await page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))));
  assert.equal(saved.totalTaps,game.totalTaps+100);assert.equal(saved.progress[townId],137);
  assert.equal(documentLoads,1,'A loaded session must not load another document');
  assert.equal(await page.evaluate(()=>performance.timeOrigin),started,'A loaded session must not reload');assert.deepEqual(errors,[]);
  assert(samples.at(-1).heap<=samples[0].heap+32*1024*1024,JSON.stringify(samples));
  if(samples[0].wasm>0)assert(samples.at(-1).wasm<=samples[0].wasm+32*1024*1024,JSON.stringify(samples));
  fs.writeFileSync(output,JSON.stringify(samples,null,2));
  console.log('PASS: idle, tapping and zoom preserve the campaign without reload or retained heap growth.');
  await browser.close();
})().catch(async error=>{console.error(error);await browser?.close();process.exitCode=1;});

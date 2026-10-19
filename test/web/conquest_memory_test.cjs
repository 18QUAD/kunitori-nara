// Compare the last ordinary tap, conquest and settled memory using real census geometry.
// PREFECTURE_VIEW=1 tests the prefecture map. For Nara municipal completion,
// generate GAME_FIXTURE with conquest_fixture.dart and set PREFECTURE_ID=29.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
let browser;
let activePoll;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.MEMORY_OUTPUT || '/workspace/map-conquest-memory.json';
  const scale = Number(process.env.MAP_SCALE || 24);
  const pref=process.env.PREFECTURE_ID || '24';
  const geo = JSON.parse(fs.readFileSync(path.join(__dirname, pref==='29' ? '../../assets/data/nara.json' : '../../assets/data/prefectures/'+pref+'.json')));
  const pts = geo.towns.flatMap(t => t.polygons.flat(2));
  const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
  const minX = xs.reduce((a,b)=>Math.min(a,b),Infinity), maxX = xs.reduce((a,b)=>Math.max(a,b),-Infinity), minY = ys.reduce((a,b)=>Math.min(a,b),Infinity), maxY = ys.reduce((a,b)=>Math.max(a,b),-Infinity);
  const ppd = Math.min(1020 / ((maxX-minX)*.826),1420/(maxY-minY));
  const dx=(1100-(maxX-minX)*.826*ppd)/2,dy=(1500-(maxY-minY)*ppd)/2;
  const townId = process.env.TOWN_ID || (pref==='29' ? '29205041001' : '242080950');
  const shape=geo.towns.find(t=>t.id===townId);
  const metadata=pref==='29' ? shape : JSON.parse(fs.readFileSync(path.join(__dirname,'../../assets/data/japan.json'))).towns.find(t=>t.id===townId);
  const town={...metadata,...shape};
  const fixture=process.env.GAME_FIXTURE ? JSON.parse(fs.readFileSync(process.env.GAME_FIXTURE)) : null;
  if(fixture)town.population=fixture.population;
  const homeId = pref==='29' ? '29205043001' : townId === '242081650' ? '242081210' : '242080940';
  const owned=[homeId];
  const ring=town.polygons[0][0];
  const lon=ring.reduce((a,p)=>a+p[0],0)/ring.length,lat=ring.reduce((a,p)=>a+p[1],0)/ring.length;
  const game = fixture?.game || {version: 1, quizRule: 'office-five-v1', dataset: 'nara-2020-v1',
    tapRule: 'population-v1', territoryUnit: 'town-v1', difficulty: 'standard',
    home: homeId, attackTarget: townId, owned, everOwned: owned, titles: [],
    mastered: [], seen: [], progress: {[townId]:Math.max(1,town.population)-2}, totalTaps: 160501,
    cityTaps: {[town.cityId]:Math.max(1,town.population)-2}, cityTapsComplete: true, wins: 0, losses: 0, quiz: null};
  const view = {dataset: 'nara-2020-v1', projection: '1100x1500-v1',
    center: [dx+(lon-minX)*.826*ppd, dy+(maxY-lat)*ppd], scale,
    selected: townId, cityId: process.env.PREFECTURE_VIEW ? null : town.cityId, prefectureId: pref, nationalView: false, showGeography: true};
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
  // Exclude the preceding map's adjacent-level prefetch from the conquest.
  await page.getByRole('button',{name:'攻略中の町へ',exact:true}).click({trial:true,timeout:120000});
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
  const resourceOffset=await page.evaluate(()=>performance.getEntriesByType('resource').length);
  const info=await processSession.send('SystemInfo.getProcessInfo');
  const pids=info.processInfo.filter(p=>p.type==='renderer').map(p=>p.id);
  let peakRss=0;
  const poll=activePoll=setInterval(()=>{
    let rss=0;
    for(const pid of pids){try{rss+=Number(fs.readFileSync(`/proc/${pid}/status`,'utf8').match(/VmRSS:\s+(\d+)/)[1])*1024;}catch{}}
    peakRss=Math.max(peakRss,rss);
  },50);
  await sample('before ordinary tap');
  await page.locator('button.attack-tap-native').evaluate(e=>e.click());
  await page.waitForTimeout(300);
  await sample('one tap before conquest');
  const beforeConquest={...samples.at(-1)};
  peakRss=0;
  await page.locator('button.attack-tap-native').evaluate(e=>e.click());
  const conquestStarted=Date.now();
  // Do not force garbage collection during the immediate post-conquest peak.
  for(const delay of [50,200,750,3000]){
    await page.waitForTimeout(Math.max(0,delay-(Date.now()-conquestStarted)));
    const m=await cdp.send('Performance.getMetrics');
    const v={stage:'conquest +'+(Date.now()-conquestStarted)+'ms',heap:m.metrics.find(v=>v.name==='JSHeapUsedSize').value,
      wasm:await page.evaluate(()=>window.flutterCanvasKit.HEAPU8.buffer.byteLength)};
    samples.push(v);console.log(JSON.stringify(v));
  }
  const conquestPeakRss=peakRss;clearInterval(poll);
  await sample('after animation and GC');
  await page.waitForTimeout(10000);await sample('settled');
  clearInterval(poll);
  const resources=await page.evaluate(offset=>performance.getEntriesByType('resource').slice(offset).map(e=>e.name),resourceOffset);
  assert(!resources.some(url=>/\/(?:map_images|map_tiles_uniform|border_tiles|water_mesh|prefectures)\/|\/nara\.json/.test(url)),'A conquest must reuse current map geometry and background images');
  console.log('new resources',resources);
  console.log('conquest peak renderer RSS',conquestPeakRss);
  fs.writeFileSync(output,JSON.stringify({beforeConquest,samples,conquestPeakRss,resources},null,2));
  const saved=await page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))));
  assert.equal(saved.totalTaps,game.totalTaps+2);assert(saved.owned.includes(townId));assert.equal(saved.progress[townId],undefined);
  assert.equal(documentLoads,1,'A loaded session must not load another document');
  assert.equal(await page.evaluate(()=>performance.timeOrigin),started,'A loaded session must not reload');assert.deepEqual(errors,[]);
  assert(samples.at(-1).heap<=samples[0].heap+32*1024*1024,JSON.stringify(samples));
  if(samples[0].wasm>0)assert(samples.at(-1).wasm<=samples[0].wasm+32*1024*1024,JSON.stringify(samples));

  console.log('PASS: conquest persisted without reload.');
  await browser.close();
})().catch(async error=>{console.error(error);clearInterval(activePoll);await browser?.close();process.exitCode=1;});

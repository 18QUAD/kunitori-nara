// Exercise persisted checkpoints and JSON export, then recover a crashed renderer.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
let browser;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.MEMORY_OUTPUT || '/workspace/diagnostics-browser.json';
  const scale = Number(process.env.MAP_SCALE || 8);
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
  const context = await browser.newContext({viewport: {width: 375, height: 667}, deviceScaleFactor: 2, isMobile: true, hasTouch: true});
  let page = await context.newPage();
  await page.addInitScript(({game, view}) => {
    performance.setResourceTimingBufferSize(5000);
    if (!localStorage.getItem('flutter.kunitori.nara.v1')) localStorage.setItem('flutter.kunitori.nara.v1', JSON.stringify(JSON.stringify(game)));
    if (!localStorage.getItem('flutter.kunitori.nara.mapView.v1')) localStorage.setItem('flutter.kunitori.nara.mapView.v1', JSON.stringify(JSON.stringify(view)));
  }, {game, view});
  const automaticUploads=[];
  await page.context().route('**/*',r=>{
    const url=new URL(r.request().url());
    if(url.pathname==='/diagnostics' && url.hostname.endsWith('.workers.dev')) {
      if(r.request().method()==='POST')automaticUploads.push(JSON.parse(r.request().postData()));
      return r.fulfill({status:200,contentType:'application/json',
        headers:{'Access-Control-Allow-Origin':'*'},body:'{"ok":true}'});
    }
    return url.origin===new URL(base).origin?r.continue():r.abort();
  });
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('crash',()=>errors.push('Renderer crashed'));
  let documentLoads=0;page.on('load',()=>documentLoads++);
  await page.goto(base,{waitUntil:'networkidle'});
  await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:120000});
  await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
  for(const label of ['背景地図の読込完了','境界線画像の読込完了']) await page.getByLabel(label,{exact:true}).or(page.getByText(label,{exact:true})).first().waitFor({timeout:120000});
  const getReport = () => page.evaluate(() => JSON.parse(window.kunitoriDiagnostics.report()));
  for(let i=0;i<2;i++) {await page.locator('.attack-tap-native').click(); await page.waitForTimeout(100);}
  let report=await getReport();
  let current=report.sessions.find(s=>s.id===report.currentSession);
  assert(current.events.some(e=>e.event==='game_loaded'));
  assert(current.events.some(e=>e.event==='images_load_end'));
  assert(current.events.some(e=>e.event==='conquest_before'));
  assert(current.events.some(e=>e.event==='conquest_after'));
  assert(current.events.some(e=>e.state.prefecture==='24'));
  assert(current.events.some(e=>e.memory.canvasKitHeapBytes>0));
  console.log('Conquest checkpoints verified.');
  await page.getByRole('button',{name:'設定',exact:true}).click();
  await page.getByText('診断ログ',{exact:true}).click();
  await page.getByText('JSONを保存',{exact:true}).waitFor();
  const downloadEvent=page.waitForEvent('download');
  await page.getByText('JSONを保存',{exact:true}).click();
  const download=await downloadEvent;await download.saveAs(output);
  const exported=JSON.parse(fs.readFileSync(output,'utf8'));
  assert.equal(exported.currentSession,current.id);
  assert(exported.sessions.some(s=>s.events.some(e=>e.event==='conquest_after')));
  await page.getByText('閉じる',{exact:true}).click();
  const before=await page.evaluate(()=>({game:localStorage.getItem('flutter.kunitori.nara.v1'),view:localStorage.getItem('flutter.kunitori.nara.mapView.v1')}));
  // Kill the renderer without an unload callback. Reopen the app in this
  // browser context, just as a user may reopen after Safari loses the tab.
  const cdp=await page.context().newCDPSession(page);
  const crash=page.waitForEvent('crash');
  void cdp.send('Page.crash').catch(()=>{});await crash;
  page = await page.context().newPage();
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base,{waitUntil:'networkidle',timeout:120000});
  await page.waitForFunction(()=>window.kunitoriDiagnostics?.report);
  report=await getReport();
  const recovered=report.sessions.find(s=>s.id===report.currentSession);
  assert.equal(recovered.previousSession,null); // New tab, no false cause attribution.
  assert.equal(report.sessions.find(s=>s.id===current.id).ended,false);
  assert(report.sessions.find(s=>s.id===current.id).events.some(e=>e.event==='conquest_after'));
  const after=await page.evaluate(()=>({game:localStorage.getItem('flutter.kunitori.nara.v1'),view:localStorage.getItem('flutter.kunitori.nara.mapView.v1')}));
  assert.deepEqual(after,before);
  await page.waitForTimeout(2500);
  assert(automaticUploads.some(p=>p.sessions.some(s=>s.id===current.id && s.events.some(e=>e.event==='conquest_after'))), 'Recovered pre-crash log must upload automatically');
  assert.equal(errors.filter(e=>e!=='Renderer crashed').length,0,errors.join('\n'));
  console.log('PASS browser: actual conquest/map/memory checkpoints, settings JSON download, renderer crash recovery, automatic upload and unchanged game/view saves.');
  await browser.close();
})().catch(async error=>{console.error(error);if(browser)await browser.close();process.exitCode=1;});

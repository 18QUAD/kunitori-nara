// Representative synthetic campaign at the logged scale and rounded map center.
// dart test/web/exact_zoom_fixture.dart /tmp/zoom-ids.json
// ZOOM_FIXTURE=/tmp/zoom-ids.json BASE_URL=http://127.0.0.1:8770/kunitori-nara/ node test/web/exact_zoom_memory_test.cjs
// Stress a loaded map under a 512 MiB JS heap limit; record JS, WASM and renderer memory.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
let browser;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.MEMORY_OUTPUT || '/workspace/exact-zoom-memory.json';
  let scale = Number(process.env.MAP_SCALE || 6.443794328325407);
  const geo = JSON.parse(fs.readFileSync(path.join(__dirname, '../../assets/data/prefectures/24.json')));
  const pts = geo.towns.flatMap(t => t.polygons.flat(2));
  const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
  const minX = xs.reduce((a,b)=>Math.min(a,b),Infinity), maxX = xs.reduce((a,b)=>Math.max(a,b),-Infinity), minY = ys.reduce((a,b)=>Math.min(a,b),Infinity), maxY = ys.reduce((a,b)=>Math.max(a,b),-Infinity);
  const ppd = Math.min(1020 / ((maxX-minX)*.826),1420/(maxY-minY));
  scale = 128 * 2**Math.max(-3,Math.min(7,Math.round(Math.log2(scale*ppd*2/128)))) / (ppd*2);
  const dx=(1100-(maxX-minX)*.826*ppd)/2,dy=(1500-(maxY-minY)*ppd)/2;
  const townId = process.env.TOWN_ID || '242081510';
  const town=geo.towns.find(t=>t.id===townId);
  const meta={towns:JSON.parse(fs.readFileSync(process.env.ZOOM_FIXTURE || '/workspace/zoom-valid-town-ids.json')).map(id=>({id,cityId:id.slice(0,5)}))};
  const owned=meta.towns.filter(t=>t.cityId==='24208').map(t=>t.id);
  for(const t of meta.towns){if(owned.length>=560)break;if(t.id.startsWith('24')&&!owned.includes(t.id))owned.push(t.id);}
  const homeId = townId === '242081650' ? '242081210' : '242080940';
  const ring=town.polygons[0][0];
  const lon=ring.reduce((a,p)=>a+p[0],0)/ring.length,lat=ring.reduce((a,p)=>a+p[1],0)/ring.length;
  const game = {version: 1, quizRule: 'office-five-v1', dataset: 'nara-2020-v1',
    tapRule: 'population-v1', territoryUnit: 'town-v1', difficulty: 'standard',
    home: homeId, attackTarget: null, owned: [...new Set([homeId,...owned])].slice(0,560), everOwned: [...new Set([homeId,...owned])].slice(0,560), titles: [],
    mastered: [], seen: [], progress: {}, totalTaps: Number(process.env.FIXTURE_TAPS || 160501),
    cityTaps: {'24208': 484}, cityTapsComplete: true, wins: 0, losses: 0, quiz: null};
  const view = {dataset: 'nara-2020-v1', projection: '1100x1500-v1',
    center: [331.2,597.3], scale,
    selected: townId, cityId: '24208', prefectureId: '24', nationalView: false, showGeography: true};
  browser = await chromium.launch({executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    proxy: process.env.HTTPS_PROXY ? {server: process.env.HTTPS_PROXY, bypass: '127.0.0.1,localhost'} : undefined,
    args: ['--no-sandbox','--js-flags=--max-old-space-size=512']});
  const page = await browser.newPage({viewport: {width: 375, height: 667}, deviceScaleFactor: 2, isMobile: true, hasTouch: true});
  await page.addInitScript(() => {
    const state=window.textureDiagnostics={live:{},events:[],phase:'boot',peakBytes:0};
    let seq=0;const ids=new WeakMap(),bound=new WeakMap();
    for(const name of ['WebGLRenderingContext','WebGL2RenderingContext']) {
      const proto=window[name]?.prototype;if(!proto)continue;
      const create=proto.createTexture,bind=proto.bindTexture,del=proto.deleteTexture;
      proto.createTexture=function(...a){const t=create.apply(this,a);if(t)ids.set(t,++seq);return t;};
      proto.bindTexture=function(target,t){let b=bound.get(this);if(!b)bound.set(this,b={});b[target]=ids.get(t);return bind.call(this,target,t);};
      proto.deleteTexture=function(t){delete state.live[ids.get(t)];return del.call(this,t);};
      for(const method of ['texImage2D','texStorage2D']) {
        const original=proto[method];if(!original)continue;
        proto[method]=function(...a){
          const w=method==='texStorage2D'?a[3]:a.length>=9?a[3]:a[5]?.width;
          const h=method==='texStorage2D'?a[4]:a.length>=9?a[4]:a[5]?.height;
          if(Number.isFinite(w)&&Number.isFinite(h)) {
            const id=bound.get(this)?.[a[0]];
            if(id)state.live[id]={w,h,bytes:w*h*4};
            const bytes=Object.values(state.live).reduce((n,x)=>n+x.bytes,0);
            state.peakBytes=Math.max(state.peakBytes,bytes);
            if(state.events.length<4096)state.events.push({phase:state.phase,method,w,h,bytes});
          }
          return original.apply(this,a);
        };
      }
    }
  });
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

    const metrics=await cdp.send('Performance.getMetrics');
    const heap=metrics.metrics.find(m=>m.name==='JSHeapUsedSize').value;
    const wasm=await page.evaluate(()=>window.flutterCanvasKit?.HEAPU8?.buffer.byteLength || 0);
    const info=await processSession.send('SystemInfo.getProcessInfo');
    let rss=0;
    for(const proc of info.processInfo.filter(p=>p.type==='renderer')){
      try{rss+=Number(fs.readFileSync(`/proc/${proc.id}/status`,'utf8').match(/VmRSS:\s+(\d+)/)[1])*1024;}catch{}
    }
    const textures=await page.evaluate(()=>({live:window.textureDiagnostics.live,peakBytes:window.textureDiagnostics.peakBytes}));
    samples.push({stage,heap,wasm,rss,textures});console.log(stage,JSON.stringify({heapMiB:heap/1048576,wasmMiB:wasm/1048576,rssMiB:rss/1048576,estimatedTextureMiB:Object.values(textures.live).reduce((n,x)=>n+x.bytes,0)/1048576}));
    if(process.env.EXPECT_RELEASED_SOURCES==='1') {
      const report=await page.evaluate(()=>JSON.parse(window.kunitoriDiagnostics.report()));
      const ends=report.sessions.flatMap(s=>s.events).filter(e=>e.event==='images_load_end');
      assert(ends.length>0);
      assert(ends.every(e=>e.state.imageCache.runtimeRasters===0),'Finished layers must not generate map images');
    }
  }
  let peakRss=0;
  const processInfo=await processSession.send('SystemInfo.getProcessInfo');
  const pids=processInfo.processInfo.filter(p=>p.type==='renderer'||p.type==='GPU').map(p=>p.id);
  const poll=setInterval(()=>{let rss=0;for(const pid of pids){try{rss+=Number(fs.readFileSync(`/proc/${pid}/status`,'utf8').match(/VmRSS:\s+(\d+)/)[1])*1024;}catch{}}peakRss=Math.max(peakRss,rss);},50);
  try {
    await sample('loaded');
    for(let i=0;i<3;i++) {
      for(const name of ['拡大','縮小']) {
        await page.evaluate(phase=>window.textureDiagnostics.phase=phase,`${i}-${name}`);
        await page.getByRole('button',{name,exact:true}).evaluate(e=>e.click());
        await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
        const until=Date.now()+120000;
        while(!(await page.getByRole('button',{name:'攻略中の町へ',exact:true}).or(page.getByRole('button',{name:'本拠地へ',exact:true})).first().isEnabled())) {
          if(Date.now()>until)throw Error('Image retirement/zoom controls did not finish');
          await page.waitForTimeout(20);
        }
        for(const label of ['背景地図の読込完了','境界線画像の読込完了'])await page.getByLabel(label,{exact:true}).or(page.getByText(label,{exact:true})).first().waitFor({timeout:120000});
        const captured=await page.evaluate(()=>({x:scrollX,y:scrollY,view:JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.mapView.v1')))}));
        assert.equal(captured.x,0,'Test must not scroll the document while clicking map semantics');
        assert.equal(captured.y,0);
        assert(Math.abs(captured.view.scale-(name==='拡大'?scale*2:scale))<1e-8);
        await sample(`${i}-${name}`);
      }
    }
    await page.screenshot({path:output.replace(/\.json$/,'.png')});
    const textures=await page.evaluate(()=>window.textureDiagnostics);
    const saved=await page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))));
    assert.equal(saved.totalTaps,game.totalTaps);assert.deepEqual(saved.owned,game.owned);
    assert.equal(documentLoads,1);assert.equal(await page.evaluate(()=>performance.timeOrigin),started);assert.deepEqual(errors,[]);
    fs.writeFileSync(output,JSON.stringify({samples,textures,peakRss},null,2));
    console.log('PASS prepared adjacent scales, 560 territories, no reload; peak RSS',peakRss);
  } finally {clearInterval(poll);await browser.close();}
})().catch(async error=>{console.error(error);await browser?.close();process.exitCode=1;});

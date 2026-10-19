// Real prepared-image regression: isolated synthetic campaign, offline navigation,
// scale changes, taps/conquest, shared 32 MiB budget and no document reload.
// PROFILE_DIR must be a dedicated test profile; it preserves downloaded packs.
const {chromium}=require('playwright');
const fs=require('node:fs'),assert=require('node:assert/strict'),path=require('node:path'),os=require('node:os');
const root=path.resolve(__dirname,'../..');
const outputDir=process.env.OUTPUT_DIR||fs.mkdtempSync(path.join(os.tmpdir(),'kunitori-prepared-audit-'));
fs.mkdirSync(outputDir,{recursive:true});
const output=name=>path.join(outputDir,name);
const profileDir=process.env.PROFILE_DIR||path.join(outputDir,'profile');
console.log('Audit artifacts:',outputDir);
const base=process.env.BASE_URL||'http://127.0.0.1:8770/kunitori-nara/';
let context,page,ticker;const result={actions:[],samples:[],errors:[]};let phase='download';
(async()=>{
 context=await chromium.launchPersistentContext(profileDir,{executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,proxy:process.env.HTTPS_PROXY?{server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'}:undefined,args:['--no-sandbox'],viewport:{width:375,height:667},deviceScaleFactor:2,isMobile:true,hasTouch:true});
 await context.route('**/*',r=>(new URL(r.request().url()).origin===new URL(base).origin||new URL(r.request().url()).hostname==='raw.githubusercontent.com')?r.continue():r.abort());page=context.pages()[0];for(const other of context.pages().slice(1))await other.close();
 const all=JSON.parse(fs.readFileSync(path.join(root,'assets/data/japan.json'))).towns;
 const target=all.find(t=>t.id==='242080620');
 const owned=[...new Set([...all.filter(t=>t.id.startsWith('24')).slice(0,560).map(t=>t.id),...target.neighbors,'242080940'])];
 await context.addInitScript(owned=>{
  if(window.top!==window)return;
  {
   localStorage.setItem('flutter.kunitori.nara.v1',JSON.stringify(JSON.stringify({version:1,quizRule:'office-five-v1',dataset:'nara-2020-v1',tapRule:'population-v1',difficulty:'standard',home:'242080940',attackTarget:'242080620',owned,everOwned:owned,titles:[],mastered:[],seen:[],progress:{'242080620':37},totalTaps:123456,cityTaps:{'24208':484},cityTapsComplete:true,wins:0,losses:0,quiz:null})));
   localStorage.setItem('flutter.kunitori.nara.mapView.v1',JSON.stringify(JSON.stringify({dataset:'nara-2020-v1',projection:'1100x1500-v1',center:[720,680],scale:.26,selected:null,cityId:null,prefectureId:'24',nationalView:true,showGeography:true})));
   localStorage.setItem('preparedAuditSeeded','1');
  }
  window.audit={events:[],longtasks:[],parses:[],canvases:[]};const originalTransfer=OffscreenCanvas.prototype.transferToImageBitmap;OffscreenCanvas.prototype.transferToImageBitmap=function(){const t=performance.now();const v=originalTransfer.call(this);if(audit.canvases.length<500)audit.canvases.push({width:this.width,height:this.height,ms:performance.now()-t});return v;};const parse=JSON.parse;
  JSON.parse=function(s,...args){const t=performance.now();const value=parse.call(this,s,...args);if(typeof s==='string'&&s.length>500000)audit.parses.push({chars:s.length,ms:performance.now()-t,at:t});return value;};
  let diagnostics;Object.defineProperty(window,'kunitoriDiagnostics',{configurable:true,get(){return diagnostics;},set(v){diagnostics=v;const rec=v.record;v.record=function(e,s,i){audit.events.push({at:performance.now(),event:e,data:parse(s||'{}'),wasm:window.flutterCanvasKit?.HEAPU8?.buffer?.byteLength});return rec.call(this,e,s,i);};}});
  new PerformanceObserver(list=>audit.longtasks.push(...list.getEntries().map(e=>({at:e.startTime,ms:e.duration})))).observe({type:'longtask',buffered:true});
 },owned);
 page.on('pageerror',e=>result.errors.push(e.message));page.on('crash',()=>result.errors.push('crash'));
 const cdp=await context.newCDPSession(page);await cdp.send('Performance.enable');await cdp.send('Profiler.enable');await cdp.send('Profiler.start');
 ticker=setInterval(async()=>{try{const h=await cdp.send('Runtime.getHeapUsage');const wasm=await page.evaluate(()=>window.flutterCanvasKit?.HEAPU8?.buffer?.byteLength||0);result.samples.push({at:Date.now(),phase,...h,wasm});}catch{}},1000);
 const started=Date.now();await page.goto(base,{waitUntil:'domcontentloaded'});console.log('upgrade download/startup waiting');
 await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:600000});await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
 async function ready(){
  for(const label of ['背景地図の読込完了','境界線画像の読込完了'])await page.getByLabel(label,{exact:true}).or(page.getByText(label,{exact:true})).first().waitFor({timeout:120000});
  await page.waitForFunction(()=>audit.events.filter(e=>e.event==='images_load_start').length===audit.events.filter(e=>e.event==='images_load_end').length,{},{timeout:120000});
  const home=page.getByRole('button',{name:'攻略中の町へ',exact:true});const end=Date.now()+120000;while(!await home.isEnabled()){if(Date.now()>end)throw Error('controls timeout');await page.waitForTimeout(50);}
 }
 await ready();
 const expectedImages=JSON.parse(fs.readFileSync(path.join(root,'build/web/map-image-manifest.json')));
 const expectedRuntime=JSON.parse(fs.readFileSync(path.join(root,'build/web/runtime-data-manifest.json')));
 const downloaded=await page.evaluate(()=>audit.events.filter(e=>e.event==='map_storage_progress').at(-1)?.data);
 assert.equal(downloaded.mapDownloadTotal,expectedImages.assets.length+expectedRuntime.chunks.length,'The active worker must use the complete current build');
 assert.equal(downloaded.mapDownloadBytes,expectedImages.bytes+expectedRuntime.bytes,'The active worker must finish saving the current build');
 fs.writeFileSync(output('prepared-map-startup.cpuprofile'),JSON.stringify((await cdp.send('Profiler.stop')).profile));console.log('initial ready',Date.now()-started);phase='national';
 const readyTimeOrigin=await page.evaluate(()=>performance.timeOrigin);assert.equal(await page.evaluate(()=>kunitoriMapMemory.get()),32);await context.setOffline(true);
 const report=async(name)=>{const h=await cdp.send('Runtime.getHeapUsage');const wasm=await page.evaluate(()=>window.flutterCanvasKit?.HEAPU8?.buffer?.byteLength);console.log(name,'JS',Math.round(h.usedSize/1048576),'WASM',Math.round(wasm/1048576));};
 async function save(){fs.writeFileSync(output('prepared-map-browser.json'),JSON.stringify({...result,audit:await page.evaluate(()=>audit)},null,2));}
 async function action(name,fn){phase=name;const e0=await page.evaluate(()=>audit.events.length);const t=Date.now();await fn();await page.waitForFunction(n=>audit.events.slice(n).some(e=>e.event==='images_load_start'),e0,{timeout:120000});await ready();await page.waitForTimeout(150);await ready();const events=await page.evaluate(e0=>audit.events.slice(e0),e0);result.actions.push({name,ms:Date.now()-t,events});console.log('ACTION',name,Date.now()-t);await report(name);await save();}
 console.log('CANVASES',JSON.stringify(await page.evaluate(()=>audit.canvases.slice(-12))));await report('national-ready');await cdp.send('HeapProfiler.collectGarbage');await report('national-after-gc');await cdp.send('Profiler.start');
 if(!process.env.SKIP_SHOTS)await page.screenshot({timeout:60000,path:output('prepared-national.png')});
 await action('home-city',()=>page.getByRole('button',{name:'攻略中の町へ',exact:true}).click());
 if(!process.env.SKIP_SHOTS)await page.screenshot({timeout:60000,path:output('prepared-nabari.png')});
 await action('city-zoom-out',()=>page.getByRole('button',{name:'縮小',exact:true}).click());
 await action('city-zoom-in',()=>page.getByRole('button',{name:'拡大',exact:true}).click());
 const prior=await page.evaluate(()=>({events:audit.events.length,resources:performance.getEntriesByType('resource').length,save:JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1')))}));
 await page.locator('button.attack-tap-native').evaluate(async e=>{for(let i=0;i<100;i++){e.click();await new Promise(r=>setTimeout(r,20));}});await page.waitForTimeout(1000);
 const after=await page.evaluate(prior=>({events:audit.events.slice(prior.events),resources:performance.getEntriesByType('resource').slice(prior.resources).map(e=>e.name),save:JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1')))}),prior);
 assert.equal(after.save.totalTaps,prior.save.totalTaps+100);assert(!after.events.some(e=>e.event==='images_load_start'));assert(!after.resources.some(p=>p.includes('/map_images/')));console.log('PASS 100 taps: no image work');
 await action('city-to-pref',()=>page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click());
 await action('pref-to-national',()=>page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click());
 await action('national-to-nara',()=>page.getByRole('button',{name:'奈良県',exact:true}).evaluate(e=>e.click()));
 await action('nara-to-sakurai',()=>page.getByRole('button',{name:/^桜井市/}).first().evaluate(e=>e.click()));
 for(let n=0;n<5 && await page.getByRole('button',{name:'拡大',exact:true}).isEnabled();n++)await action('sakurai-zoom-'+n,()=>page.getByRole('button',{name:'拡大',exact:true}).click());
 if(!process.env.SKIP_SHOTS)await page.screenshot({timeout:60000,path:output('prepared-sakurai-fine.png')});
 await action('sakurai-to-nara',()=>page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click());
 await action('nara-to-national',()=>page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click());
 await action('national-to-hokkaido',()=>page.getByRole('button',{name:'北海道',exact:true}).evaluate(e=>e.click()));
 if(!process.env.SKIP_SHOTS)await page.screenshot({timeout:60000,path:output('prepared-hokkaido.png')});
 await action('hokkaido-to-national',()=>page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click());
 await action('return-home-city',()=>page.getByRole('button',{name:'攻略中の町へ',exact:true}).click());
 await action('wide-portrait-resize',()=>page.setViewportSize({width:800,height:1200}));if(!process.env.SKIP_SHOTS)await page.screenshot({timeout:60000,path:output('prepared-desktop.png')});
 await action('phone-resize',()=>page.setViewportSize({width:375,height:667}));
 const campaign=await page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))));
 const remaining=target.population-campaign.progress[target.id];assert(remaining>0);
 await page.locator('button.attack-tap-native').evaluate(async(e,n)=>{for(let i=0;i<n;i++){e.click();if(i%20===19)await new Promise(r=>setTimeout(r,0));}},remaining-1);
 await page.waitForTimeout(300);
 const beforeWin=await page.evaluate(()=>({events:audit.events.length,resources:performance.getEntriesByType('resource').length,save:JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1')))}));
 await page.locator('button.attack-tap-native').evaluate(e=>e.click());await page.waitForTimeout(1500);
 const won=await page.evaluate(before=>({events:audit.events.slice(before.events),resources:performance.getEntriesByType('resource').slice(before.resources).map(e=>e.name),save:JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1')))}),beforeWin);
 assert(won.save.owned.includes(target.id));assert.equal(won.save.totalTaps,beforeWin.save.totalTaps+1);
 assert(!won.events.some(e=>e.event==='images_load_start'));assert(!won.resources.some(p=>p.includes('/map_images/')));console.log('PASS conquest: no background/boundary loads or regeneration');
 phase='idle';await page.waitForTimeout(2000);await cdp.send('HeapProfiler.collectGarbage');await report('idle-after-gc');
 fs.writeFileSync(output('prepared-map-actions.cpuprofile'),JSON.stringify((await cdp.send('Profiler.stop')).profile));await save();
 const audit=await page.evaluate(()=>audit);assert(!audit.events.some(e=>/images_(?:load|index)_error/.test(e.event)),JSON.stringify(audit.events.filter(e=>e.event.includes('error'))));
 for(const e of audit.events){const cache=e.data.imageCache;if(!cache)continue;assert.equal(cache.runtimeRasters,0);assert(cache.budget.retainedImageBytes+cache.budget.compressedLimitBytes<=32*1048576);}
 assert.equal(await page.evaluate(()=>performance.timeOrigin),readyTimeOrigin,'A ready game must not reload');assert.deepEqual(result.errors,[]);console.log('PASS: offline navigation/zoom, 32 MiB image budget, no runtime map raster generation, no reload/errors');
 clearInterval(ticker);await context.close();
})().catch(async e=>{console.error(e);clearInterval(ticker);if(page){try{fs.writeFileSync(output('prepared-map-browser.json'),JSON.stringify({...result,audit:await page.evaluate(()=>audit)},null,2));console.log((await page.locator('body').innerText()).slice(-3000));if(!process.env.SKIP_SHOTS)await page.screenshot({timeout:60000,path:output('prepared-map-failure.png')});}catch{}}if(context)await context.close();process.exitCode=1;});

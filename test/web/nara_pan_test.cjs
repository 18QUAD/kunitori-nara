// Synthetic Nara-city campaign: exercise repeated pan and measure native text
// layout creation, without sending or changing a real user's saved game.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const output=process.env.OUTPUT_DIR;assert(output);fs.mkdirSync(output,{recursive:true});
const base='http://127.0.0.1:8770/kunitori-nara/';let context,page,timer;
const report={errors:[],samples:[],gestures:0};
(async()=>{
 context=await chromium.launchPersistentContext('/workspace/prepared-download-fast-profile',{executablePath:'/usr/bin/chromium',headless:true,proxy:process.env.HTTPS_PROXY?{server:process.env.HTTPS_PROXY,bypass:'localhost,127.0.0.1'}:undefined,args:['--no-sandbox'],viewport:{width:375,height:667},deviceScaleFactor:2,isMobile:true,hasTouch:true});
 await context.route('**/*',r=>new URL(r.request().url()).origin===new URL(base).origin||new URL(r.request().url()).hostname==='raw.githubusercontent.com'?r.continue():r.abort());
 page=context.pages()[0];for(const other of context.pages().slice(1))await other.close();
 const owned=JSON.parse(fs.readFileSync('test/fixtures/national_transition_owned.json'));
 await context.addInitScript(owned=>{
  localStorage.setItem('flutter.kunitori.nara.v1',JSON.stringify(JSON.stringify({version:1,quizRule:'office-five-v1',dataset:'nara-2020-v1',tapRule:'population-v1',difficulty:'standard',home:owned[0],owned,everOwned:owned,titles:[],mastered:[],seen:[],progress:{},totalTaps:123456,cityTaps:{},cityTapsComplete:true,wins:0,losses:0,quiz:null})));
  localStorage.setItem('flutter.kunitori.nara.mapView.v1',JSON.stringify(JSON.stringify({dataset:'nara-2020-v1',projection:'1100x1500-v1',center:[500,250],scale:2.6602770028169163,selected:'292018070',cityId:'29201',prefectureId:'29',nationalView:false,showGeography:true})));
 },owned);
 page.on('pageerror',e=>report.errors.push(e.message));page.on('crash',()=>report.errors.push('crash'));
 const cdp=await context.newCDPSession(page);
 await page.goto(base,{waitUntil:'domcontentloaded'});
 await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:600000});await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
 for(const text of ['背景地図の読込完了','境界線画像の読込完了'])await page.getByLabel(text,{exact:true}).or(page.getByText(text,{exact:true})).first().waitFor({timeout:120000});
 await page.getByRole('button',{name:/^(本拠地へ|攻略中の町へ)$/}).waitFor();
 console.log('Nara city ready');
 await context.setOffline(true);
 const origin=await page.evaluate(()=>performance.timeOrigin);
 await page.evaluate(()=>{
  window.nativeParagraphs=0;
  const builder=window.flutterCanvasKit.ParagraphBuilder;
  const original=builder.MakeFromFontCollection;
  builder.MakeFromFontCollection=function(...args){nativeParagraphs++;return original.apply(this,args);};
 });
 await cdp.send('HeapProfiler.collectGarbage');
 const started=Date.now();
 timer=setInterval(async()=>{try{report.samples.push({at:Date.now(),...await cdp.send('Runtime.getHeapUsage'),...await page.evaluate(()=>({paragraphs:nativeParagraphs,wasm:window.flutterCanvasKit.HEAPU8.buffer.byteLength}))});}catch{}},500);
 for(let gesture=0;gesture<20;gesture++){
  const direction=gesture%2===0?1:-1;
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,x:170,y:245}]});
  for(let step=1;step<=6;step++){
   await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:170+direction*step*6,y:245+direction*step*2}]});
   await page.waitForTimeout(40);
  }
  await page.waitForTimeout(200);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await page.waitForTimeout(180);report.gestures++;if(report.gestures%5===0)console.log('Gestures',report.gestures);
 }
 await page.waitForTimeout(2000);
 report.durationMs=Date.now()-started;report.paragraphs=await page.evaluate(()=>nativeParagraphs);
 assert(report.paragraphs>0,'Native paragraph instrumentation must observe actual paints');
 report.documentReloaded=origin!==await page.evaluate(()=>performance.timeOrigin);
 report.build=await page.evaluate(()=>JSON.parse(kunitoriDiagnostics.report()).sessions.at(-1).build);
 assert.equal(report.documentReloaded,false);assert.deepEqual(report.errors,[]);
 if(process.env.MAX_PARAGRAPHS)assert(report.paragraphs<Number(process.env.MAX_PARAGRAPHS),'Pan must not relayout every offscreen town');
 fs.writeFileSync(path.join(output,'nara-pan.json'),JSON.stringify(report,null,2));
 await page.screenshot({path:path.join(output,'nara-pan.png')});
 console.log(JSON.stringify({build:report.build,gestures:report.gestures,paragraphs:report.paragraphs,durationMs:report.durationMs,jsPeakMiB:Math.max(...report.samples.map(s=>s.usedSize))/1048576,wasmMiB:Math.max(...report.samples.map(s=>s.wasm))/1048576,errors:report.errors}));
 clearInterval(timer);await context.close();
})().catch(async e=>{console.error(e);clearInterval(timer);if(page)try{console.log((await page.locator('body').innerText()).slice(-1000));}catch{}if(context)await context.close();process.exitCode=1;});

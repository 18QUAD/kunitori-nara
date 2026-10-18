// Verify actual sea pixels and hit testing in the release, including fresh geometry URLs.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {PNG} = require('pngjs');
let browser;
(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output = process.env.SCREENSHOT_DIR || '/tmp/kunitori-coastline';
  fs.mkdirSync(output,{recursive:true});
  const sea = {lon:137.25386138,lat:34.75205628};
  const center = [40+(sea.lon-122)*42,40+(46-sea.lat)*50];
  const key = 'flutter.kunitori.nara.v1', mapKey = 'flutter.kunitori.nara.mapView.v1';
  browser = await chromium.launch({executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    proxy:process.env.HTTPS_PROXY ? {server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'} : undefined,args:['--no-sandbox']});
  const page = await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('response',r=>{if(r.url().startsWith(base) && r.status()>=400) errors.push(`${r.status()} ${r.url()}`)});
  await page.addInitScript(({key,mapKey,center})=>{
    performance.setResourceTimingBufferSize(10000);
    localStorage.setItem(key,JSON.stringify(JSON.stringify({version:1,quizRule:'office-five-v1',dataset:'nara-2020-v1',tapRule:'population-v1',territoryUnit:'town-v1',difficulty:'standard',home:'29205043001',attackTarget:'29205041001',titles:['大和への第一歩'],mastered:[],seen:[],wins:0,losses:0,quiz:null,owned:['29205043001'],everOwned:['29205043001'],progress:{'29205041001':7},totalTaps:7,cityTaps:{'29205':7},cityTapsComplete:true})));
    localStorage.setItem(mapKey,JSON.stringify(JSON.stringify({dataset:'nara-2020-v1',projection:'1100x1500-v1',center,scale:12,selected:null,cityId:null,showGeography:true,prefectureId:'29',nationalView:true})));
  },{key,mapKey,center});
  await page.route('**/*',r=>new URL(r.request().url()).origin===new URL(base).origin ? r.continue() : r.abort());
  await page.goto(base,{waitUntil:'networkidle'});
  await page.locator('flutter-view').waitFor({state:'attached',timeout:120000});
  const placeholder=page.locator('flt-semantics-placeholder');
  const map=page.getByLabel('全国地図',{exact:true});
  // Network-idle can precede the first Flutter frame. Enable semantics only
  // once its placeholder exists, or continue if semantics are already active.
  await Promise.race([
    placeholder.waitFor({state:'attached',timeout:120000}),
    map.waitFor({state:'attached',timeout:120000}),
  ]);
  if(await placeholder.count()) await placeholder.evaluate(e=>e.click());
  await page.screenshot({path:path.join(output,'startup-map.png')});
  await map.waitFor({timeout:120000});
  await page.getByLabel('背景地図の読込完了',{exact:true}).or(page.getByText('背景地図の読込完了',{exact:true})).first().waitFor({timeout:60000});
  await page.getByLabel('境界線画像の読込完了',{exact:true}).or(page.getByText('境界線画像の読込完了',{exact:true})).first().waitFor({timeout:60000});
  const view=()=>page.evaluate(k=>JSON.parse(JSON.parse(localStorage.getItem(k))),mapKey);
  assert.equal((await view()).nationalView,true);
  assert(await page.evaluate(()=>performance.getEntriesByType('resource').some(e=>/japan\.json\?coast=20261015-v1/.test(e.name))));
  assert(!(await page.evaluate(()=>performance.getEntriesByType('resource').some(e=>e.name.includes('map_labels/national.json')))));
  const box=await map.boundingBox();
  const middle={x:box.x+box.width/2,y:box.y+box.height/2};
  fs.writeFileSync(path.join(output,'sea-point.json'),JSON.stringify({middle,box,view:await view()}));
  const seaShot=await page.screenshot({path:path.join(output,'mikawa-sea.png')});
  const pixels=PNG.sync.read(seaShot);
  const seaOffset=(Math.round(middle.y)*pixels.width+Math.round(middle.x))*4;
  assert.deepEqual([...pixels.data.subarray(seaOffset,seaOffset+4)],[18,43,50,255],
    'Sea must retain the map background, without terrain or blue water');
  // Semantics actions synthesize a scene-center tap; use real pointer routing
  // for geographic hit testing after enabling semantics for startup detection.
  await page.addStyleTag({content:'flt-semantics { pointer-events: none !important; }'});
  await page.touchscreen.tap(middle.x,middle.y);
  await page.waitForTimeout(250);
  fs.writeFileSync(path.join(output,'after-sea.json'),JSON.stringify(await view()));
  await page.screenshot({path:path.join(output,'after-sea.png')});
  assert.equal((await view()).nationalView,true,'Sea must not select any prefecture');
  const scale=(await view()).scale;
  const land={lon:137.2193,lat:34.8264}; // Gamagori city hall, on land.
  await page.touchscreen.tap(middle.x+(land.lon-sea.lon)*42*scale,middle.y+(sea.lat-land.lat)*50*scale);
  await page.waitForFunction(k=>{const v=JSON.parse(JSON.parse(localStorage.getItem(k)));return v.prefectureId==='23' && !v.nationalView},mapKey,{timeout:120000});
  await page.getByLabel('背景地図の読込完了',{exact:true}).or(page.getByText('背景地図の読込完了',{exact:true})).first().waitFor({timeout:60000});
  assert(await page.evaluate(()=>performance.getEntriesByType('resource').some(e=>/prefectures\/23\.json\?coast=20261015-v1/.test(e.name))));
  await page.screenshot({path:path.join(output,'aichi-coast.png')});
  const saved=await page.evaluate(k=>JSON.parse(JSON.parse(localStorage.getItem(k))),key);
  assert.equal(saved.home,'29205043001');assert.equal(saved.progress['29205041001'],7);assert.equal(saved.totalTaps,7);
  assert.deepEqual(errors,[]);
  console.log('PASS: sea is outside national hit regions; land selects Aichi; fresh coastal geometry, images, names and saved progress load correctly.');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(async()=>{await browser?.close()});

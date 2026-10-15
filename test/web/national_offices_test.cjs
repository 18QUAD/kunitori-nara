const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
let browser;
(async () => {
  const base=process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/';
  const output=process.env.SCREENSHOT_DIR || '/tmp/national-offices-browser';
  fs.mkdirSync(output,{recursive:true});
  const key='flutter.kunitori.nara.v1', mapKey='flutter.kunitori.nara.mapView.v1';
  browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    proxy:process.env.HTTPS_PROXY ? {server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'} : undefined,
    args:['--no-sandbox','--js-flags=--max-old-space-size=512']});
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:3,isMobile:true,hasTouch:true});
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('crash',()=>errors.push('Renderer crashed'));
  page.on('response',r=>{if(r.url().startsWith(base) && r.status()>=400) errors.push(`${r.status()} ${r.url()}`)});
  await page.addInitScript(({key,mapKey})=>{
    localStorage.setItem(key,JSON.stringify(JSON.stringify({version:1,quizRule:'office-five-v1',dataset:'nara-2020-v1',tapRule:'population-v1',territoryUnit:'town-v1',difficulty:'standard',home:'29205043001',attackTarget:'29205041001',titles:['大和への第一歩'],mastered:[],seen:[],wins:0,losses:0,quiz:null,owned:['29205043001'],everOwned:['29205043001'],progress:{'29205041001':7},totalTaps:7,cityTaps:{'29205':7},cityTapsComplete:true})));
    localStorage.setItem(mapKey,JSON.stringify(JSON.stringify({dataset:'nara-2020-v1',projection:'1100x1500-v1',center:[550,750],scale:0.35,selected:null,cityId:null,showGeography:true,prefectureId:'27',nationalView:false})));
  },{key,mapKey});
  await page.route('https://**',r=>new URL(r.request().url()).origin===new URL(base).origin?r.continue():r.abort());
  await page.goto(base,{waitUntil:'networkidle'});
  await page.locator('flutter-view').waitFor({state:'attached',timeout:120000});
  const placeholder=page.locator('flt-semantics-placeholder');
  const ward=page.getByRole('button',{name:/^大阪市北区役所/});
  await Promise.race([placeholder.waitFor({state:'attached',timeout:120000}),ward.waitFor({state:'attached',timeout:120000})]);
  if(await placeholder.count()) await placeholder.evaluate(e=>e.click());
  await ward.waitFor({timeout:120000});
  await page.getByLabel('背景地図の読込完了',{exact:true}).waitFor({timeout:60000});
  await page.getByRole('button',{name:/^大阪市役所/}).waitFor();
  await page.screenshot({path:path.join(output,'osaka-prefecture-offices.png')});
  await ward.evaluate(e=>e.click());
  await page.waitForFunction(k=>{const v=JSON.parse(JSON.parse(localStorage.getItem(k)));return v.cityId==='27127' && v.selected?.startsWith('27127')},mapKey,{timeout:60000});
  await page.getByLabel('背景地図の読込完了',{exact:true}).waitFor({timeout:60000});
  await page.getByRole('button',{name:/^大阪市役所/}).waitFor();
  await ward.waitFor();
  assert.equal(await page.getByRole('button',{name:/^堺市役所/}).count(),0,'Ward view must hide unrelated headquarters');
  await page.screenshot({path:path.join(output,'osaka-ward-offices.png')});
  await page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click();
  await page.waitForFunction(k=>JSON.parse(JSON.parse(localStorage.getItem(k))).cityId===null,mapKey);
  await page.getByRole('button',{name:/^大阪市役所/}).evaluate(e=>e.click());
  await page.waitForFunction(k=>JSON.parse(JSON.parse(localStorage.getItem(k))).cityId==='27127',mapKey);
  const saved=await page.evaluate(k=>JSON.parse(JSON.parse(localStorage.getItem(k))),key);
  assert.equal(saved.home,'29205043001');assert.equal(saved.attackTarget,'29205041001');
  assert.equal(saved.progress['29205041001'],7);assert.equal(saved.totalTaps,7);assert.equal(saved.quiz,null);
  assert.deepEqual(errors,[]);
  console.log('PASS: DPR 3, city/ward headquarters on prefecture and ward maps, navigation and unchanged Nara campaign; no new quiz or loading errors.');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(async()=>{await browser?.close()});

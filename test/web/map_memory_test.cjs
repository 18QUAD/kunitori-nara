// Stress the release with mobile DPR=3, repeated large-prefecture loads and zoom.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
let browser;
(async () => {
  browser = await chromium.launch({executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    proxy:process.env.HTTPS_PROXY ? {server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'} : undefined,
    args:['--no-sandbox','--js-flags=--max-old-space-size=512']});
  const page = await browser.newPage({viewport:{width:390,height:844}, deviceScaleFactor:3,isMobile:true,hasTouch:true});
  const errors = [];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('crash',()=>errors.push('Renderer crashed'));
  await page.addInitScript(() => {
    localStorage.setItem('flutter.kunitori.nara.v1',JSON.stringify(JSON.stringify({version:1,
      quizRule:'office-five-v1',dataset:'nara-2020-v1',tapRule:'population-v1',territoryUnit:'town-v1',difficulty:'standard',
      home:'29205043001',attackTarget:'29205041001',owned:['29205043001'],everOwned:['29205043001'],titles:['大和への第一歩'],
      mastered:[],seen:[],progress:{'29205041001':7},totalTaps:7,cityTaps:{'29205':7},cityTapsComplete:true,wins:0,losses:0,quiz:null})));
    localStorage.setItem('flutter.kunitori.nara.mapView.v1',JSON.stringify(JSON.stringify({
      dataset:'nara-2020-v1',projection:'1100x1500-v1',center:[720,680],scale:0.25,
      selected:null,cityId:null,showGeography:true,prefectureId:'29',nationalView:true})));
  });
  await page.goto(process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/',{waitUntil:'networkidle'});
  const placeholder=page.locator('flt-semantics-placeholder');
  if(await placeholder.count()) await placeholder.evaluate(e=>e.click());
  await page.getByLabel('全国地図',{exact:true}).waitFor({timeout:120000});
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Performance.enable');
  const samples=[];
  for (const name of ['北海道','東京都','大阪府','北海道','東京都','大阪府']) {
    // Accessible prefecture hit areas overlap at the nationwide fit scale.
    await page.getByRole('button',{name,exact:true}).evaluate(e=>e.click());
    await page.getByRole('button',{name:'1段上の地図を表示',exact:true}).waitFor({timeout:60000});
    await page.getByLabel('背景地図の読込完了',{exact:true}).waitFor({timeout:60000});
    for(let i=0;i<3;i++) await page.getByRole('button',{name:'拡大',exact:true}).click();
    await page.waitForTimeout(150);
    await page.getByLabel('背景地図の読込完了',{exact:true}).waitFor({timeout:60000});
    for(let i=0;i<3;i++) await page.getByRole('button',{name:'縮小',exact:true}).click();
    await page.getByRole('button',{name:'1段上の地図を表示',exact:true}).click();
    await page.getByLabel('全国地図',{exact:true}).waitFor();
    await cdp.send('HeapProfiler.collectGarbage');
    const metrics=await cdp.send('Performance.getMetrics');
    const heap=metrics.metrics.find(m=>m.name==='JSHeapUsedSize').value;
    samples.push(heap);
    console.log(name,'JS heap after collection:',Math.round(heap/1024/1024),'MiB');
  }
  // Re-visiting the same three prefectures must not retain another copy of them.
  assert(Math.max(...samples.slice(3)) <= Math.max(...samples.slice(0,3)) + 24*1024*1024, JSON.stringify(samples));
  const saved=await page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))));
  assert.equal(saved.home,'29205043001');
  assert.equal(saved.progress['29205041001'],7);
  assert.equal(saved.totalTaps,7);
  assert.deepEqual(errors,[]);
  console.log('PASS: DPR 3, 512MiB V8 old-space limit, repeated prefectures, zoom, bounded retained heap and intact campaign.');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(async()=>{await browser?.close()});

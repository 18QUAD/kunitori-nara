// Run against the release-compiled test/web/attack_contact_harness.dart.
// Dropping browser-delivered releases reproduces the old permanently blocked button.
const assert=require('node:assert/strict'),http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
const root=process.env.HARNESS_DIR||'/workspace/scratch/attack-contact-harness';
const index=`<!doctype html><style>html,body{margin:0}#app-host{width:100vw;height:100vh}</style><meta name="viewport" content="width=device-width,initial-scale=1"><div id="app-host"></div>
<script>window.kunitoriViewport={top:()=>0,bottom:()=>0};window.blockReleases=false;
for(const type of ['pointerup','pointercancel'])window.addEventListener(type,e=>{if(blockReleases)e.stopImmediatePropagation();},true);</script>
<script src="flutter.js"></script><script>fetch('flutter_bootstrap.js').then(r=>r.text()).then(text=>{
const config=text.match(/_flutter.buildConfig = (.*?);/);if(!config)throw Error('Missing build config');
eval('_flutter.buildConfig = '+config[1]);_flutter.loader.load({config:{canvasKitBaseUrl:'canvaskit/'},onEntrypointLoaded:async init=>{const app=await init.initializeEngine({hostElement:document.getElementById('app-host')});await app.runApp();}});});</script>`;
const mime={'.js':'application/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.ttf':'font/ttf'};
const server=http.createServer((req,res)=>{
 const name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
 if(name==='/'){res.setHeader('Content-Type','text/html');return res.end(index);}
 const file=path.resolve(root,'.'+name);if(!file.startsWith(path.resolve(root)+path.sep)){res.statusCode=403;return res.end();}
 if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.statusCode=404;return res.end();}
 res.setHeader('Content-Type',mime[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
 try{
  browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox']});
  const context=await browser.newContext({viewport:{width:375,height:667},deviceScaleFactor:2,isMobile:true,hasTouch:true});
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:'+server.address().port+'/');
  const button=page.locator('.attack-tap-native').first();await button.waitFor({state:'visible',timeout:60000});
  const box=await button.boundingBox(),left={id:1,x:box.x+40,y:box.y+80},right={id:2,x:box.x+120,y:box.y+80},third={id:3,x:box.x+80,y:box.y+110};
  const cdp=await context.newCDPSession(page);let expected=0;
  const touch=(type,touchPoints)=>cdp.send('Input.dispatchTouchEvent',{type,touchPoints});
  const count=async()=>{await page.waitForTimeout(30);assert.equal(await page.locator('body').getAttribute('data-taps'),String(expected));};
  await touch('touchStart',[left]);expected++;await count();
  await touch('touchStart',[left,right]);await count();
  await touch('touchEnd',[right]); // primary leaves, secondary remains.
  await touch('touchStart',[right,third]);await count(); // still the same group.
  await touch('touchEnd',[]);await count();
  console.log('PASS real overlapping/alternating fingers remain one contact group');
  // Lose every pointerup from this group, while the browser knows all fingers released.
  await touch('touchStart',[left,right]);expected++;await count();
  await page.evaluate(()=>window.blockReleases=true);await touch('touchEnd',[]);
  await page.evaluate(()=>window.blockReleases=false);
  await touch('touchStart',[left]);expected++;await count();await touch('touchEnd',[]);
  console.log('PASS lost releases recover on the next genuine primary touch without app switching');
  // A fresh gesture can begin outside the button. That primary pointer must
  // also retire stale contacts before its second finger presses the button.
  const outside={id:9,x:10,y:100};
  await touch('touchStart',[left]);expected++;await count();
  await page.evaluate(()=>window.blockReleases=true);await touch('touchEnd',[]);
  await page.evaluate(()=>window.blockReleases=false);
  await touch('touchStart',[outside]);await count();
  await touch('touchStart',[outside,left]);expected++;await count();
  await touch('touchEnd',[]);
  console.log('PASS lost release recovers when the next primary finger starts outside the button');
  await touch('touchStart',[left]);expected++;await count();
  await page.evaluate(()=>window.blockReleases=true);await touch('touchEnd',[]);
  await page.evaluate(()=>window.blockReleases=false);
  await touch('touchStart',[outside,left]);expected++;await count();
  await touch('touchEnd',[]);
  console.log('PASS simultaneous outside/inside contacts recover without a lost count');


  await touch('touchStart',[left]);expected++;await count();
  await page.evaluate(()=>window.blockReleases=true);await touch('touchCancel',[]);await page.evaluate(()=>window.blockReleases=false);
  await touch('touchStart',[left]);expected++;await count();await touch('touchEnd',[]);
  console.log('PASS lost cancellation recovers on the next genuine touch');
  for(let i=0;i<25;i++){await touch('touchStart',[left,right]);expected++;await touch('touchEnd',[]);}
  await count();
  await page.mouse.move(left.x,left.y);await page.mouse.down();expected++;await count();
  await page.evaluate(()=>window.blockReleases=true);await page.mouse.up();await page.evaluate(()=>window.blockReleases=false);
  await page.mouse.click(left.x,left.y);expected++;await count();
  await button.focus();await button.press('Enter');expected++;await count();
  await button.press('Space');expected++;await count();
  await button.evaluate(e=>e.click());expected++;await count();
  await button.evaluate(e=>e.dispatchEvent(new PointerEvent('click',{bubbles:true,pointerType:'touch',detail:0})));await count();
  await page.locator('#harness-toggle').click();await page.waitForFunction(()=>document.querySelector('.attack-tap-native').disabled);assert(await button.isDisabled());
  await button.evaluate(e=>e.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,button:0,pointerType:'touch',pointerId:77,isPrimary:true})));await count();
  await page.locator('#harness-toggle').click();await page.waitForFunction(()=>!document.querySelector('.attack-tap-native').disabled);assert(await button.isEnabled());
  await touch('touchStart',[left]);expected++;await count();await touch('touchEnd',[]);
  await page.setViewportSize({width:844,height:390});
  await page.waitForFunction(()=>document.querySelectorAll('.attack-tap-native').length===2);
  await page.waitForTimeout(200);
  const boxes=await Promise.all((await page.locator('.attack-tap-native').all()).map(b=>b.boundingBox()));
  assert(boxes.every(b=>b&&b.width>0&&b.height>0));
  const hands=boxes.map((b,i)=>({id:i+21,x:b.x+b.width/2,y:b.y+b.height/2}));
  await touch('touchStart',hands);expected+=2;await count();await touch('touchEnd',[]);
  await touch('touchStart',[hands[0]]);expected++;await count();
  await touch('touchStart',hands);expected++;await count();
  await touch('touchEnd',[]);
  await page.setViewportSize({width:375,height:667});
  await page.waitForFunction(()=>document.querySelectorAll('.attack-tap-native').length===1);
  await page.waitForTimeout(200);
  const restored=await button.boundingBox();
  await touch('touchStart',[{id:31,x:restored.x+80,y:restored.y+80}]);expected++;await count();await touch('touchEnd',[]);
  console.log('PASS landscape both hands, overlapping left/right contacts, and portrait restoration');
  assert.deepEqual(errors,[]);
  console.log('PASS rapid groups, lost mouse release, keyboard/accessible activation, disabled input and re-enable; accepted count:',expected);
 }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1;});

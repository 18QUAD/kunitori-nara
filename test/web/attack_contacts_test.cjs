// Real multi-touch contacts against the release, using an isolated synthetic save.
// PROFILE_DIR reuses a dedicated test profile's already downloaded map packs.
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
(async()=>{
 const output=process.env.OUTPUT_DIR||fs.mkdtempSync(path.join(os.tmpdir(),'kunitori-contact-taps-'));
 fs.mkdirSync(output,{recursive:true});
 const base=process.env.BASE_URL||'http://127.0.0.1:8770/kunitori-nara/';
 const context=await chromium.launchPersistentContext(process.env.PROFILE_DIR||path.join(output,'profile'),{
  executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,
  proxy:process.env.HTTPS_PROXY?{server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'}:undefined,
  args:['--no-sandbox'],viewport:{width:375,height:667},deviceScaleFactor:2,isMobile:true,hasTouch:true,
 });
 try {
 const page=context.pages()[0];for(const other of context.pages().slice(1))await other.close();
 const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('crash',()=>errors.push('crash'));
 const timer=setInterval(async()=>{try {console.log('STATE',(await page.locator('body').innerText()).slice(0,400));}catch{}},20000);
 context.on('close',()=>clearInterval(timer));
 await context.route('**/*',r=>(new URL(r.request().url()).origin===new URL(base).origin||new URL(r.request().url()).hostname==='raw.githubusercontent.com')?r.continue():r.abort());
 const towns=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../assets/data/japan.json'))).towns;
 const target=towns.find(t=>t.id==='242080620');
 const owned=[...new Set([...towns.filter(t=>t.id.startsWith('24')).slice(0,560).map(t=>t.id),...target.neighbors,'242080940'])];
 await context.addInitScript(owned=>{
  if(window.top!==window)return;
  localStorage.setItem('flutter.kunitori.nara.v1',JSON.stringify(JSON.stringify({version:1,quizRule:'office-five-v1',dataset:'nara-2020-v1',tapRule:'population-v1',difficulty:'standard',home:'242080940',attackTarget:'242080620',owned,everOwned:owned,titles:[],mastered:[],seen:[],progress:{'242080620':37},totalTaps:123456,cityTaps:{'24208':484},cityTapsComplete:true,wins:0,losses:0,quiz:null})));
  localStorage.setItem('flutter.kunitori.nara.mapView.v1',JSON.stringify(JSON.stringify({dataset:'nara-2020-v1',projection:'1100x1500-v1',center:[720,680],scale:1,selected:'242080620',cityId:'24208',prefectureId:'24',nationalView:false,showGeography:true})));
 },owned);
 await page.goto(base,{waitUntil:'domcontentloaded'});
 await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:600000});
 await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
 const attack=page.locator('button.attack-tap-native');await attack.waitFor({state:'visible',timeout:120000});
 for(const label of ['背景地図の読込完了','境界線画像の読込完了'])await page.getByLabel(label,{exact:true}).or(page.getByText(label,{exact:true})).first().waitFor({timeout:120000});
 assert(await attack.isEnabled());await context.setOffline(true);
 const origin=await page.evaluate(()=>performance.timeOrigin);
 const initial=await page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))).totalTaps);
 let expected=0;
 const assertCount=async(n=expected)=>page.waitForFunction(({initial,n})=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))).totalTaps===initial+n,{initial,n},{timeout:10000});
 await attack.evaluate(e=>{window.contactEvents=[];for(const type of ['pointerdown','pointerup','pointercancel','click'])e.addEventListener(type,v=>contactEvents.push({type,primary:v.isPrimary,pointerType:v.pointerType,detail:v.detail}));});
 const box=await attack.boundingBox(),y=box.y+box.height/2;
 const left={id:1,x:box.x+box.width*.3,y},right={id:2,x:box.x+box.width*.7,y};
 const cdp=await context.newCDPSession(page);
 const touch=(type,touchPoints)=>cdp.send('Input.dispatchTouchEvent',{type,touchPoints});
 await touch('touchStart',[left]);await assertCount(++expected); // Still held.
 await touch('touchStart',[left,right]);await assertCount(++expected); // Non-primary finger.
 await page.waitForTimeout(900);await assertCount();
 await touch('touchEnd',[left]);await touch('touchEnd',[]);await page.waitForTimeout(150);await assertCount();
 console.log('PASS: both fingers counted on contact before release; hold/release add nothing');
 for(let i=0;i<25;i++){
  await touch('touchStart',[left,right]);expected+=2;
  await touch('touchEnd',[]);
 }
 await assertCount();console.log('PASS: 50 rapid contacts counted exactly');
 await touch('touchStart',[left]);await assertCount(++expected);
 await touch('touchMove',[{...left,y:y+10}]);
 await touch('touchCancel',[]);await page.waitForTimeout(150);await assertCount();
 await page.mouse.move(left.x,y);await page.mouse.down();await assertCount(++expected);
 await page.mouse.up();await page.waitForTimeout(150);await assertCount();
 await page.mouse.click(left.x,y,{button:'right'});await page.waitForTimeout(150);await assertCount();
 await attack.focus();await attack.press('Enter');await assertCount(++expected);
 await attack.press('Space');await assertCount(++expected);
 await attack.evaluate(e=>e.click());await assertCount(++expected);
 await attack.evaluate(e=>e.dispatchEvent(new PointerEvent('click',{bubbles:true,pointerType:'touch',detail:0})));
 await page.waitForTimeout(150);await assertCount();
 console.log('PASS: cancellation/mouse release/right click do not add; keyboard and accessible-style click add once');
 await attack.evaluate(e=>{e.disabled=true;e.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,button:0,pointerType:'touch'}));e.click();e.disabled=false;});
 await page.waitForTimeout(150);await assertCount();
 await page.getByRole('button',{name:'設定',exact:true}).click();
 await page.waitForFunction(()=>getComputedStyle(document.querySelector('button.attack-tap-native')).visibility==='hidden');
 await attack.evaluate(e=>{e.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,button:0,pointerType:'touch'}));e.click();});
 await page.waitForTimeout(200);await assertCount();
 assert.equal(await page.evaluate(()=>performance.timeOrigin),origin);
 const contacts=await page.evaluate(()=>contactEvents);
 assert(contacts.some(e=>e.type==='pointerdown'&&e.primary===false),'Real non-primary contacts must be exercised');
 assert(contacts.some(e=>e.type==='click'&&e.detail>0),'Real compatibility clicks must be exercised');
 const saved=await page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))));
 assert.equal(saved.progress[target.id],37+expected);
 assert.equal(saved.cityTaps['24208'],484+expected);
 assert.deepEqual(errors,[]);
 fs.writeFileSync(path.join(output,'attack-contacts.json'),JSON.stringify({expected,initial,contacts,errors,offline:true},null,2));
 console.log('PASS: modal blocks contacts, no reload/errors; total accepted contacts/activations:',expected);
 } finally {await context.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});

// Run against a release build served at BASE_URL with Playwright installed.
const {chromium}=require('playwright'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium',args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:390,height:750},isMobile:true,hasTouch:true});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const fixture={version:1,quizRule:'office-five-v1',dataset:'nara-2020-v1',
  tapRule:'population-v1',territoryUnit:'town-v1',difficulty:'standard',
  home:'29205043001',attackTarget:'29205041001',owned:['29205043001'],
  everOwned:['29205043001'],titles:['大和への第一歩'],mastered:[],seen:[],progress:{},totalTaps:0,
  cityTaps:{},cityTapsComplete:true,wins:0,losses:0,quiz:null};
 await page.addInitScript(game=>localStorage.setItem('flutter.kunitori.nara.v1',JSON.stringify(JSON.stringify(game))),fixture);
 await page.route('https://cyberjapandata.gsi.go.jp/**',route=>route.abort());
 await page.goto(process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/',{waitUntil:'networkidle'});
 await page.locator('flutter-view').waitFor({state:'attached',timeout:60000});
 const placeholder=page.locator('flt-semantics-placeholder'); if(await placeholder.count())await placeholder.evaluate(e=>e.click());
 const attack=page.getByRole('button',{name:'タップで進軍 · 1人',exact:true});await attack.waitFor({timeout:60000});
 const result=await page.evaluate(async()=>{
  const host=document.getElementById('app-host');
  const text=[...host.querySelectorAll('flt-semantics span')].find(e=>e.textContent.length>15);
  if(!text)throw Error('No game text found');
  const attack=host.querySelector('button.attack-tap-native');
  if(!attack)throw Error('No native attack button');
  if(attack.textContent!=='' || attack.children.length!==0)throw Error('Attack has selectable content');
  if(!getComputedStyle(attack).backgroundImage.includes('assets/assets/icons/tap.png'))throw Error('No tap image');
  const rect=attack.getBoundingClientRect();
  if(rect.width<300)throw Error('Guard does not cover full attack area');
  const touchStart=(target,x,y)=>{const event=new Event('touchstart',{bubbles:true,cancelable:true});Object.defineProperty(event,'changedTouches',{value:[{clientX:x,clientY:y}]});target.dispatchEvent(event);return event.defaultPrevented};
  if(touchStart(attack,rect.left+15,rect.top+rect.height/2))throw Error('Native button touch was canceled');
  if(touchStart(text,20,200))throw Error('Map gesture blocked');
  const style=getComputedStyle(text);if(style.userSelect!=='none'||style.webkitUserSelect!=='none')throw Error('Selectable game text');
  for(const type of ['selectstart','contextmenu']){
   const event=new Event(type,{bubbles:true,cancelable:true});text.dispatchEvent(event);if(!event.defaultPrevented)throw Error(type+' not blocked');
  }
  const select=()=>{const range=document.createRange();range.selectNodeContents(text);getSelection().removeAllRanges();getSelection().addRange(range)};
  select();await new Promise(r=>setTimeout(r,30));if(!getSelection().isCollapsed)throw Error('Selectionchange failed');
  select();host.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}));if(!getSelection().isCollapsed)throw Error('Pointer cleanup failed');
  // Check field exceptions in the same host used by Flutter's text inputs.
  const input=document.createElement('input');input.value='検索の編集';host.append(input);
  if(getComputedStyle(input).userSelect!=='text')throw Error('Input CSS blocked');
  for(const type of ['selectstart','contextmenu']){const event=new Event(type,{bubbles:true,cancelable:true});input.dispatchEvent(event);if(event.defaultPrevented)throw Error('Input menu blocked');}
  input.focus();input.setSelectionRange(0,2);document.dispatchEvent(new Event('selectionchange'));if(input.selectionEnd!==2)throw Error('Input selection cleared');input.remove();
  const editor=document.createElement('div');editor.contentEditable='true';editor.textContent='編集テスト';host.append(editor);
  const range=document.createRange();range.selectNodeContents(editor);getSelection().removeAllRanges();getSelection().addRange(range);await new Promise(r=>setTimeout(r,30));if(getSelection().toString()!=='編集テスト')throw Error('Editable selection cleared');getSelection().removeAllRanges();editor.remove();
  return text.textContent;
 });
 const game=()=>page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('flutter.kunitori.nara.v1'))));
 for(let i=0;i<8;i++)await attack.tap();
 await assertCount(8);
 const box=await attack.boundingBox();const cdp=await page.context().newCDPSession(page);
 const point={x:box.x+box.width/2,y:box.y+box.height/2};
 await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point]});
 await page.waitForTimeout(900);
 await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 await assertCount(9);
 await attack.focus();await attack.press('Enter');await assertCount(10);
 const mapBefore=await page.evaluate(()=>localStorage.getItem('flutter.kunitori.nara.mapView.v1'));
 await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:100,y:280}]});
 for(let step=1;step<=5;step++){
  await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:100+step*15,y:280+step*10}]});
  await page.waitForTimeout(40);
 }
 await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 await page.waitForFunction(before=>{const value=localStorage.getItem('flutter.kunitori.nara.mapView.v1');return value&&value!==before},mapBefore,{timeout:5000});
 assert.equal((await game()).totalTaps,10);
 await page.getByRole('button',{name:'設定',exact:true}).click();
 await page.waitForFunction(()=>getComputedStyle(document.querySelector('button.attack-tap-native')).visibility==='hidden');
 await page.getByText('キャラ・吹き出し',{exact:true}).click();
 await page.getByRole('button',{name:'tips設定を閉じる',exact:true}).waitFor();
 assert.equal(await page.locator('button.attack-tap-native').isVisible(),false);
 await page.getByRole('button',{name:'tips設定を閉じる',exact:true}).click();
 await attack.waitFor({state:'visible'});
 assert.equal((await game()).totalTaps,10);
 async function assertCount(count){await page.waitForFunction(expected=>{const stored=localStorage.getItem('flutter.kunitori.nara.v1');return stored&&JSON.parse(JSON.parse(stored)).totalTaps===expected},count,{timeout:5000});}
 await page.setViewportSize({width:360,height:528});
 await page.waitForFunction(()=>{const r=document.querySelector('button.attack-tap-native').getBoundingClientRect();return r.right<=360&&r.bottom<=528&&r.height>40});
 await attack.tap();await assertCount(11);
 await page.setViewportSize({width:750,height:390});
 await page.waitForFunction(()=>getComputedStyle(document.querySelector('button.attack-tap-native')).visibility==='hidden');
 await page.setViewportSize({width:360,height:528});await attack.waitFor({state:'visible'});
 await attack.tap();await assertCount(12);
 assert(await attack.count());assert.equal(await page.evaluate(()=>getSelection().isCollapsed),true);assert.equal(errors.length,0);
 console.log('PASS: game CSS, selection/context menus, selectionchange/pointer cleanup, editable exceptions native image-only button, uncanceled touches, exact tap counts, long press, keyboard, map drag, modal visibility, resize and portrait guard',result);
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});

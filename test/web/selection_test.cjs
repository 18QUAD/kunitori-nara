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
 await page.goto(process.env.BASE_URL || 'http://127.0.0.1:8766/kunitori-nara/',{waitUntil:'networkidle'});
 await page.locator('flutter-view').waitFor({state:'attached',timeout:60000});
 const placeholder=page.locator('flt-semantics-placeholder'); if(await placeholder.count())await placeholder.evaluate(e=>e.click());
 const attack=page.getByRole('button',{name:'タップで進軍 · 1人',exact:true});await attack.waitFor({timeout:60000});
 const result=await page.evaluate(async()=>{
  const host=document.getElementById('app-host');
  const text=[...host.querySelectorAll('flt-semantics span')].find(e=>e.textContent.length>15);
  if(!text)throw Error('No game text found');
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
 for(let i=0;i<8;i++)await attack.tap();
 assert(await attack.count());assert.equal(await page.evaluate(()=>getSelection().isCollapsed),true);assert.equal(errors.length,0);
 console.log('PASS: game CSS, selection/context menus, selectionchange/pointer cleanup, editable exceptions and repeated mobile taps',result);
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});

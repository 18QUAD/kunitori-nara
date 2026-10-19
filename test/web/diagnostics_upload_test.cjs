const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const code=fs.readFileSync('web/diagnostics.js','utf8');
const store=()=>{const map=new Map();return {getItem:k=>map.get(k)||null,setItem:(k,v)=>map.set(k,v)};};
function boot(localStorage,sessionStorage,fetcher){
  const handlers={},timers=[];
  const window={addEventListener:(k,f)=>handlers[k]=f};
  const document={visibilityState:'visible',addEventListener:(k,f)=>handlers[k]=f};
  vm.runInNewContext(code,{window,document,localStorage,sessionStorage,
    navigator:{userAgent:'iPhone',onLine:true},performance:{getEntriesByType:()=>[]},
    fetch:fetcher,TextEncoder,AbortController,Date,Math,
    setTimeout:(f,ms)=>{timers.push({f,ms});return timers.length;},clearTimeout(){},setInterval(){},
  });
  return {api:window.kunitoriDiagnostics,timers,handlers};
}
(async()=>{
 const local=store(),tab=store();
 const legacy={id:'old-local-run',build:'diagnostics-20261019-v1',events:[{event:'conquest_before',state:{prefecture:'24'}}]};
 local.setItem('kunitori.diagnostics.v1',JSON.stringify({version:1,sessions:[legacy]}));
 local.setItem('flutter.kunitori.nara.v1','keep-game');local.setItem('flutter.kunitori.nara.mapView.v1','keep-map');
 tab.setItem('kunitori.diagnostics.v1.tab',legacy.id);
 const sent=[];let fail=true;
 const a=boot(local,tab,async(url,options)=>{
   sent.push({url,options});if(fail)throw Error('offline');return {ok:true};
 });
 assert(a.timers.some(t=>t.ms===2000));
 const snapshot=local.getItem('kunitori.diagnostics.v1');
 await a.api.upload();assert.equal(local.getItem('kunitori.diagnostics.v1'),snapshot);
 fail=false;await a.api.upload();
 const packet=JSON.parse(sent.at(-1).options.body);
 assert(packet.sessions.some(s=>s.id===legacy.id));
 assert(packet.sessions.some(s=>s.previousSession===legacy.id));
 assert(sent[0].url.endsWith('/diagnostics'));
 assert.equal(sent[0].options.credentials,'omit');assert(!sent[0].options.body.includes('keep-game'));
 assert(new TextEncoder().encode(sent[0].options.body).length<=40*1024);
 assert(JSON.parse(a.api.report()).lastUploaded);
 assert.equal(local.getItem('flutter.kunitori.nara.v1'),'keep-game');
 assert.equal(local.getItem('flutter.kunitori.nara.mapView.v1'),'keep-map');
 let release,calls=0;
 const b=boot(local,store(),()=>{calls++;return new Promise(resolve=>release=resolve);});
 const first=b.api.upload();await b.api.upload();assert.equal(calls,1);release({ok:true});await first;
 console.log('PASS automatic upload: previous-version recovery, offline retry, single in-flight request, bounded packet and unchanged saves.');
})().catch(e=>{console.error(e);process.exitCode=1;});

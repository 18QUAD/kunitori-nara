const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('web/diagnostics.js','utf8'),key='kunitori.diagnostics.v1';
function storage(){const values=new Map(),writes=new Map();return {values,writes,getItem:k=>values.get(k)||null,setItem(k,v){values.set(k,v);writes.set(k,(writes.get(k)||0)+1);}};}
function boot(local,tab){
 let now=1700000000000;const handlers={},intervals=[],frames=[];
 class Clock extends Date {constructor(...a){super(...(a.length?a:[now]));}static now(){return now;}}
 const document={visibilityState:'visible',baseURI:'https://18quad.github.io/kunitori-nara/',addEventListener(k,f){handlers[k]=f;}};
 const window={addEventListener(k,f){handlers[k]=f;}};
 vm.runInNewContext(source,{window,document,localStorage:local,sessionStorage:tab,navigator:{userAgent:'iPhone test',onLine:false},
 performance:{getEntriesByType:()=>[]},Date:Clock,Math,URL,requestAnimationFrame:f=>frames.push(f),
 setInterval:(f,ms)=>intervals.push({f,ms}),setTimeout(){}});
 return {api:window.kunitoriDiagnostics,handlers,document,advance:ms=>now+=ms,frame:()=>frames.shift()(),
 interval:ms=>intervals.filter(i=>i.ms===ms).forEach(i=>i.f()),report:()=>JSON.parse(window.kunitoriDiagnostics.report())};
}
const local=storage(),tab=storage();local.setItem('flutter.kunitori.nara.v1','save-untouched');
const a=boot(local,tab),initialWrites=local.writes.get(key);
const stages=['input','calculated','update_requested','save_requested'];
for(const phase of stages)a.api.record('trace_tap',JSON.stringify({operation:17,phase,selected:'242161270',totalTaps:305439}),true);
assert.equal(local.writes.get(key),initialWrites,'Stages do not rewrite the full state ring');
// Terminate before frame submission, then recover the missing end from the next document.
const b=boot(local,tab),report=b.report(),old=report.sessions[0];
assert.equal(report.sessions.at(-1).previousEnd,'no_pagehide_observed');
assert.deepEqual(old.events.filter(e=>e.event==='trace_tap').map(e=>e.state.phase),stages);
assert(old.events.filter(e=>e.event==='trace_tap').every(e=>e.state.operation===17));
for(let i=0;i<10000;i++)b.api.record('trace_image',JSON.stringify({phase:'decode_start',resource:'24/image-'+i,operation:i}),true);
assert(local.getItem(key+'.trace').length<=6*1024);assert(JSON.parse(local.getItem(key+'.trace')).events.length<=24);
b.frame();b.advance(6000);b.frame();b.interval(1000);
let events=b.report().sessions.at(-1).events;
assert(events.some(e=>e.event==='browser_frame'));
assert(events.some(e=>e.event==='event_loop_delay'&&e.state.delayMs===5000));
b.handlers.error({message:'bad render',error:{stack:'frame:12\n'.repeat(800)},filename:'https://example.com/map.js?token=secret',lineno:12,colno:3});
events=b.report().sessions.at(-1).events;const error=events.findLast(e=>e.event==='browser_error');
assert.equal(error.state.resource,'/map.js');assert.equal(error.state.line,12);assert.equal(error.state.stack.length,4096);
b.advance(5000);b.interval(5000);assert.equal(b.report().sessions.at(-1).events.at(-1).state.stack,undefined);
assert.equal(local.getItem('flutter.kunitori.nara.v1'),'save-untouched');
const denied={getItem(){throw Error('denied')},setItem(){throw Error('quota')}};
assert.doesNotThrow(()=>boot(denied,denied).api.record('trace_tap','{"operation":1,"phase":"input"}',true));
console.log('PASS operation diagnostics: crash-stage recovery, operation correlation, bounded checkpoints, frame/timer progress, stack/resource details, denied storage and unchanged saves.');

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('web/diagnostics.js', 'utf8');
const key = 'kunitori.diagnostics.v1';
function storage() {
  const map = new Map();
  return {map, getItem: k => map.get(k) ?? null, setItem: (k,v) => map.set(k,v)};
}
function boot(localStorage, sessionStorage = storage(), options = {}) {
  const handlers = {}, docHandlers = {}, intervals = [];
  const window = {addEventListener: (k,f) => handlers[k] = f};
  const document = {visibilityState: 'visible', addEventListener: (k,f) => docHandlers[k] = f};
  let now = Date.now();
  class Clock extends Date {constructor(...args) {super(...(args.length ? args : [now]));} static now() {return now;}}
  vm.runInNewContext(source, {window, document, localStorage, sessionStorage,
    navigator: {userAgent: 'Safari-test'}, performance: {getEntriesByType: () => [{type: 'reload'}]},
    Date: Clock, Math, setInterval: f => intervals.push(f), setTimeout() {},
  });
  return {api: window.kunitoriDiagnostics, handlers, docHandlers, document, window,
    tick: () => {now += 5000; intervals.forEach(f => f());},
    report: () => JSON.parse(window.kunitoriDiagnostics.report()),
  };
}
const local = storage(), tab = storage();
local.setItem('flutter.kunitori.nara.v1','original-game');
local.setItem('flutter.kunitori.nara.mapView.v1','original-view');
let a = boot(local, tab);
a.api.record('conquest_before', JSON.stringify({prefecture:'24', scale:24, totalTaps:511}), true);
let r=a.report();
assert.equal(r.sessions[0].events.find(e=>e.event==='conquest_before').state.scale,24);
assert.equal(r.sessions[0].events[0].memory.jsUsedBytes,null);
assert.equal(r.sessions[0].events[0].memory.processBytes,null);
a.window.flutterCanvasKit={HEAPU8:{buffer:{byteLength:67108864}}};a.tick();
assert.equal(a.report().sessions[0].events.at(-1).memory.canvasKitHeapBytes,67108864);
// A renderer dies without pagehide; next document in the same tab keeps its record.
let b=boot(local, tab);r=b.report();
assert.equal(r.sessions.at(-1).previousEnd,'no_pagehide_observed');
assert(r.sessions[0].events.some(e=>e.event==='conquest_before'));
// Another tab must not classify this live tab as its predecessor.
let c=boot(local);assert.equal(c.report().sessions.at(-1).previousSession,null);
b.handlers.pagehide({persisted:false});
let d=boot(local,tab);assert.equal(d.report().sessions.at(-1).previousEnd,'pagehide_observed');
d.handlers.pagehide({persisted:true});d.handlers.pageshow({persisted:true});d.tick();
assert.equal(d.report().sessions.at(-1).ended,false);
// Thousands of taps update the latest state without thousands of storage writes.
const count=JSON.parse(local.getItem(key)).sessions.at(-1).events.length;
for(let i=0;i<1000;i++)d.api.record('tap',JSON.stringify({totalTaps:i}),false);
assert.equal(JSON.parse(local.getItem(key)).sessions.at(-1).events.length,count);
d.tick();assert.equal(d.report().sessions.at(-1).events.at(-1).state.totalTaps,999);
// Long use stays bounded and preserves prior runs. No game/map save modifications.
for(let i=0;i<1000;i++) d.api.record('zoom',JSON.stringify({scale:i, filler:'あ'.repeat(5000)}),true);
assert(local.getItem(key).length*2<=96*1024);
assert(JSON.parse(local.getItem(key)).sessions.length>=2);
assert(JSON.parse(local.getItem(key)).sessions.every(s=>s.events.length<=64));
assert.equal(local.getItem('flutter.kunitori.nara.v1'),'original-game');
assert.equal(local.getItem('flutter.kunitori.nara.mapView.v1'),'original-view');
// Denied/quota storage and malformed input must not break gameplay.
const denied={getItem(){throw Error('denied');},setItem(){throw Error('quota');}};
const e=boot(denied,denied);e.api.record('bad','{',true);assert.equal(e.report().storageAvailable,false);
local.setItem(key,'bad-json');assert.doesNotThrow(()=>boot(local));
console.log('PASS diagnostics: interruption recovery, normal reload/BFCache, tab isolation, memory availability, write coalescing, bounded history and save isolation.');

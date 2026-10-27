'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');const crypto=require('node:crypto');
const source=fs.readFileSync(process.argv[2]||'web/map-cache-worker.js','utf8');
const fn=source.slice(source.indexOf('function packOperation('),source.indexOf('// One eighth'));
function fixture({cached=false,corrupt=false,stall=false}={}) {
 let writes=0,downloads=0;const data=Buffer.from('bounded verified pack');const hash=crypto.createHash('sha256').update(data).digest('hex');
 const context=vm.createContext({URL,Response,Uint8Array,Array,Map,Promise,Error,AbortController,ROOT:'https://example.com/',PACK_STORE:'packs',transfers:new Map(),keyFor:p=>p[0],
  setTimeout:(fn)=>setTimeout(fn,50),clearTimeout,
  sha256:{hash:b=>crypto.createHash('sha256').update(b).digest()},
  caches:{open:async()=>({match:async()=>cached?{body:{cancel:()=>new Promise(()=>{})}}:undefined,put:async(_,response)=>{writes++;assert.deepEqual(Buffer.from(await response.arrayBuffer()),data);if(stall)await new Promise(()=>{});}})},
  fetch:async()=>{downloads++;return new Response(corrupt?Buffer.from('wrong'):data);},
 });vm.runInContext(fn,context);
 return {run:()=>context.storedPack(['pack',hash,data.length]),state:()=>({writes,downloads,transfers:context.transfers.size})};
}
test('verified bounded body is saved once',async()=>{const f=fixture();await f.run();assert.deepEqual(f.state(),{writes:1,downloads:1,transfers:0});});
test('cached response with stalled cancellation never blocks the next window',async()=>{const f=fixture({cached:true});await f.run();assert.equal(f.state().downloads,0);});
test('invalid bytes are never committed',async()=>{const f=fixture({corrupt:true});await assert.rejects(f.run(),/length mismatch/);assert.equal(f.state().writes,0);});
test('stalled disk transaction times out and releases transfer for retry',async()=>{const f=fixture({stall:true});await assert.rejects(f.run(),/save timed out/);assert.equal(f.state().transfers,0);});

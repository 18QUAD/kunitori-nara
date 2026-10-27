'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[2] || 'web/map-cache-worker.js','utf8');
const fn = source.slice(source.indexOf('async function imageProgress('),source.indexOf('async function imageStorageStatus('));
async function recover(present,saved) {
 let value=saved;
 const meta={match:async()=>value ? new Response(JSON.stringify(value)) : undefined,put:async(_,response)=>{value=await response.json();}};
 const context=vm.createContext({Response,Set,progressKey:'current-revision',PACK_STORE:'packs',keyFor:p=>p[0],caches:{open:async()=>({keys:async()=>present.map(url=>({url}))})}});
 vm.runInContext(fn,context);
 const result=await context.imageProgress({packs:[['a','hash-a',10,0,2],['b','hash-b',20,2,5],['c','hash-c',30,5,9]]},meta);
 return {result,value};
}
test('missing revision metadata recovers all stored map packs',async()=>assert.equal((await recover(['a','b','c'])).result.next,9));
test('zero cursor recovers stored packs and persists progress',async()=>assert.equal((await recover(['a','b'],{next:0})).value.next,5));
test('a missing pack stops recovery before a hole',async()=>assert.equal((await recover(['a','c'])).result.next,2));
test('first installation stays at zero',async()=>assert.equal((await recover([])).result.next,0));
test('completed cursor and cleanup flag survive startup',async()=>{
 const {result}=await recover(['a','b','c'],{next:9,cleaned:true});assert.equal(result.next,9);assert.equal(result.cleaned,true);
});

'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[2] || 'web/map-cache-worker.js', 'utf8');
const fn = source.slice(source.indexOf('async function runtimeProgress('), source.indexOf('function combinedProgress('));
async function fixture(present, saved, warm = false) {
  const entries = new Map(saved === undefined ? [] : [['progress', {next:saved}]]);
  const downloads = [];
  const chunks = ['a','b','c','d'].map(name => [name,name,10]);
  const context = vm.createContext({Response,URL,Set,RUNTIME_META:'meta',RUNTIME_STORE:'data',RUNTIME_REVISION:'new',ROOT:'https://example.com/',
    keyFor:chunk => chunk[0],
    caches:{open: async name => name === 'meta' ? {
      match:async () => entries.has('progress') ? new Response(JSON.stringify(entries.get('progress'))) : undefined,
      put:async (_,response) => entries.set('progress',await response.json()),
    } : {keys:async () => present.map(url => ({url}))}},
    downloadPackWindow:async (items,next) => {for(let i=next;i<items.length;i++) if(!present.includes(items[i][0])) downloads.push(items[i][0]);return {next:items.length};},
  });
  vm.runInContext(fn,context);
  const result = await context.runtimeProgress({chunks,bytes:40},warm);
  return {result,downloads,entries};
}
test('new revision recovers all unchanged chunks without downloading',async () => {
 const {result,downloads}=await fixture(['a','b','c','d']);
 assert.equal(result.done,true);assert.equal(result.savedBytes,40);assert.deepEqual(downloads,[]);
});
test('changed tail resumes at existing prefix and downloads only missing chunks',async () => {
 const before=await fixture(['a','b','c']);assert.equal(before.result.saved,3);
 const after=await fixture(['a','b','c'],undefined,true);assert.equal(after.result.done,true);assert.deepEqual(after.downloads,['d']);
});
test('already-created zero cursor is recovered too',async () => {
 assert.equal((await fixture(['a','b','c','d'],0)).result.done,true);
});
test('first install remains incomplete and does not skip missing chunks',async () => {
 assert.equal((await fixture([])).result.saved,0);
 assert.equal((await fixture(['a','c','d'])).result.saved,1);
});

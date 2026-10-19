const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('compressed LRU bounds bytes, shares reads, evicts oldest and retries failed reads', async () => {
  let reads=0, active=0, peak=0, fail=false;
  const context = vm.createContext({URL, Uint8Array, Response,
    self:{location:{href:'https://test.invalid/game/map-cache-worker.js'},addEventListener(){}},
    caches:{open:async()=>({match:async()=>({arrayBuffer:async()=>{
      reads++;active++;peak=Math.max(peak,active);
      await new Promise(resolve=>setTimeout(resolve,1));active--;
      if(fail){fail=false;throw Error('Disk read failed');}
      return new Uint8Array(1024*1024).buffer;
    }})})},
  });
  vm.runInContext(fs.readFileSync('web/map-cache-worker.js','utf8')+'\nglobalThis.read=readStoredBytes;globalThis.snapshot=()=>({bytes:packMemoryBytes,count:packMemory.size,pending:packReads.size});',context);
  const entry=i=>['map-packs/'+i+'.bin',String(i),1024*1024];
  await Promise.all(Array.from({length:20},()=>context.read(entry(0))));
  assert.equal(reads,1,'Concurrent images from one pack must share a disk read');
  for(let i=1;i<12;i++)await context.read(entry(i));
  assert.equal(context.snapshot().bytes,8*1024*1024);
  assert.equal(context.snapshot().count,8);
  const before=reads;await context.read(entry(11));assert.equal(reads,before);
  await context.read(entry(0));assert.equal(reads,before+1,'Evicted packs load again');
  fail=true;await assert.rejects(context.read(entry(20)),/Disk read failed/);
  await context.read(entry(20));assert.equal(context.snapshot().pending,0);
  await Promise.all(Array.from({length:12},(_,i)=>context.read(entry(30+i))));
  assert(peak<=2,'At most two disk buffers in flight');
  assert(context.snapshot().bytes<=8*1024*1024);
});

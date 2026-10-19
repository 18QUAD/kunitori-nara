const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('compressed LRU bounds bytes, shares reads, evicts oldest and retries failed reads', async () => {
  let reads=0, active=0, peak=0, fail=false;
  const settings = new Map();
  const context = vm.createContext({URL, Uint8Array, Response,
    self:{location:{href:'https://test.invalid/game/map-cache-worker.js'},addEventListener(){}},
    caches:{open:async name=>name === 'kunitori-map-images-meta-v1' ? {
      match:async key=>settings.has(key)?new Response(settings.get(key)):undefined,
      put:async(key,response)=>settings.set(key,await response.text()),
    } : ({match:async()=>({arrayBuffer:async()=>{
      reads++;active++;peak=Math.max(peak,active);
      await new Promise(resolve=>setTimeout(resolve,1));active--;
      if(fail){fail=false;throw Error('Disk read failed');}
      return new Uint8Array(1024*1024).buffer;
    }})})},
  });
  vm.runInContext(fs.readFileSync('web/map-cache-worker.js','utf8')+'\nglobalThis.read=readStoredBytes;globalThis.configure=setMemorySettings;globalThis.snapshot=()=>({bytes:packMemoryBytes,count:packMemory.size,pending:packReads.size,limit:packMemoryLimit});',context);
  const entry=i=>['map-packs/'+i+'.bin',String(i),1024*1024];
  await Promise.all(Array.from({length:20},()=>context.read(entry(0))));
  assert.equal(reads,1,'Concurrent images from one pack must share a disk read');
  for(let i=1;i<40;i++)await context.read(entry(i));
  assert.equal(context.snapshot().bytes,32*1024*1024);
  assert.equal(context.snapshot().count,32);
  const before=reads;await context.read(entry(39));assert.equal(reads,before);
  await context.read(entry(0));assert.equal(reads,before+1,'Evicted packs load again');
  await context.configure(64);
  for(let i=40;i<52;i++)await context.read(entry(i));
  assert(context.snapshot().bytes>32*1024*1024);
  await context.configure(32);
  assert(context.snapshot().bytes<=32*1024*1024,'Lowering the limit immediately evicts old bytes');
  for(const size of [64,128,256,32]){
    await context.configure(size);
    assert.equal(context.snapshot().limit,size*1024*1024);
    assert.equal(JSON.parse([...settings.values()][0]).megabytes,size);
  }
  await assert.rejects(context.configure(8),/Invalid/);
  fail=true;await assert.rejects(context.read(entry(60)),/Disk read failed/);
  await context.read(entry(60));assert.equal(context.snapshot().pending,0);
  await Promise.all(Array.from({length:12},(_,i)=>context.read(entry(70+i))));
  assert(peak<=2,'At most two disk buffers in flight');
  assert(context.snapshot().bytes<=32*1024*1024);
});

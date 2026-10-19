const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function harness(transfer, clock=()=>0) {
  const context=vm.createContext({URL,Response,Uint8Array,Date:{now:clock},transfer,
    self:{location:{href:'https://example.test/game/map-cache-worker.js'},addEventListener(){}},
  });
  vm.runInContext(fs.readFileSync('web/map-cache-worker.js','utf8')+
    '\nstoredPack=transfer;globalThis.download=downloadPackWindow;',context);
  return context.download;
}

test('a slow pack does not idle other slots; at most eight writes stay in flight',async()=>{
  const started=[];let active=0,peak=0,releaseSlow;
  const slow=new Promise(resolve=>{releaseSlow=resolve;});
  const download=harness(async n=>{
    started.push(n);active++;peak=Math.max(peak,active);
    await (n===0?slow:tick());active--;
  });
  const pending=download(Array.from({length:1000},(_,i)=>i),0,'test');
  for(let i=0;i<40;i++)await tick();
  assert(started.includes(4),'The next pack must start before the slow first pack finishes');
  assert.equal(started.length,32,'One message must not queue the entire country');
  assert.equal(peak,8);
  releaseSlow();const result=await pending;
  assert.equal(result.next,32);assert.equal(result.failure,undefined);assert.equal(active,0);
});

test('failure drains writes and resumes from the first gap while reusing later successes',async()=>{
  const saved=new Set(),reads=[];let fail=true,release,active=0,settled=false;
  const gate=new Promise(resolve=>{release=resolve;});
  const download=harness(async n=>{
    if(saved.has(n))return;
    reads.push(n);active++;
    try {
      if(n===2&&fail){fail=false;throw Error('checksum');}
      await gate;saved.add(n);
    } finally {active--;}
  });
  const packs=Array.from({length:8},(_,i)=>i);
  const pending=download(packs,0,'test').then(r=>{settled=true;return r;});
  await tick();assert.equal(settled,false);assert(active>0);
  release();const first=await pending;
  assert.equal(first.next,2);assert.match(first.failure.message,/checksum/);assert.equal(active,0);
  const second=await download(packs,first.next,'test');
  assert.equal(second.next,8);assert.equal(second.failure,undefined);
  assert.equal(reads.filter(n=>n===2).length,2);
  for(const n of [0,1,3])assert.equal(reads.filter(i=>i===n).length,1);
});

test('the time window stops starting work and still finishes outstanding writes',async()=>{
  let now=0;const started=[];
  const download=harness(async n=>{started.push(n);await tick();now=1300;},()=>now);
  const result=await download(Array.from({length:1000},(_,i)=>i),0,'test');
  assert.deepEqual(started,[0,1,2,3,4,5,6,7]);assert.equal(result.next,8);
});

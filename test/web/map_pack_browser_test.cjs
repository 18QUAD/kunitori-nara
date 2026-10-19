// Real browser/worker/cache regression for packed downloads and legacy cursors.
const {chromium} = require('playwright');
const {readFileSync} = require('node:fs');
const http = require('node:http');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const root = '/game/';
const assets = Array.from({length:100}, (_, i) => [`assets/assets/data/map_tiles_uniform/${i}.webp`, Buffer.alloc(4096, i)]);
let version = 1;
const requests = new Map();
let active = 0, peak = 0, failure = true, corrupt = true;
function fixture() {
  const entries = assets.map(([name, bytes]) => [name, sha(bytes), bytes.length]);
  const packs = [], contents = new Map();
  for (let start = 0; start < entries.length; start += 10) {
    const end = start + 10, bytes = Buffer.concat(assets.slice(start, end).map(entry => entry[1]));
    const name = `map-packs/${sha(bytes)}.bin`;
    contents.set(name, bytes);
    packs.push([name, sha(bytes), bytes.length, start, end]);
  }
  return {manifest:{schema:1,packSchema:1,revision:String(version),bytes:409600,assets:entries,packs},contents};
}
const server = http.createServer((req, res) => {
  const name = new URL(req.url, 'http://localhost').pathname.slice(root.length);
  res.setHeader('Cache-Control','no-store');
  if (name === 'seed') {res.setHeader('Content-Type','text/html');res.end('<p>seed</p>');}
  else if (name === '') {
    res.setHeader('Content-Type','text/html');
    res.end(`<div id="app-host"></div><script>window.started=false;</script><script src="map-cache.js?v=${version}"></script><script>kunitoriMapDownload.then(()=>window.started=true)</script>`);
  } else if (name === 'map-cache.js') {
    res.setHeader('Content-Type','application/javascript');res.end(readFileSync('web/map-cache.js'));
  } else if (name === 'map-cache-worker.js') {
    res.setHeader('Content-Type','application/javascript');
    res.end(`Response.prototype.clone=()=>{throw Error('No response tees');};
      const buffer=Response.prototype.arrayBuffer;Response.prototype.arrayBuffer=function(){
        if(!this.url || this.url.includes('/map-packs/'))self.packDiskReads=(self.packDiskReads||0)+1;
        return buffer.call(this);
      };` + (readFileSync('web/vendor/fast-sha256.js','utf8') + readFileSync('web/map-cache-worker.js','utf8')).replace('__MAP_IMAGE_REVISION__',String(version)));
  } else if (name === 'map-image-manifest.json') {
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify(fixture().manifest));
  } else if (fixture().contents.has(name)) {
    requests.set(name,(requests.get(name)||0)+1);
    active++;peak=Math.max(peak,active);res.on('finish',()=>active--);
    const index = fixture().manifest.packs.findIndex(pack=>pack[0]===name);
    if(index===2 && failure){failure=false;res.writeHead(503);res.end('retry');return;}
    let bytes=fixture().contents.get(name);
    if(index===3 && corrupt){corrupt=false;bytes=Buffer.from(bytes);bytes[0]^=1;}
    setTimeout(()=>res.end(bytes),150);
  } else {res.writeHead(404);res.end();} // Individual image files deliberately absent.
});
let browser;
async function cursor(page){return page.evaluate(async revision=>{
 const cache=await caches.open('kunitori-map-images-meta-v1');const r=await cache.match(new URL('__map_progress__/'+revision,location.href));return r?await r.json():{next:0};
},String(version));}
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base=`http://127.0.0.1:${server.address().port}${root}`;
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
 let context=await browser.newContext(),page=await context.newPage();
 await page.goto(base);await page.evaluate(()=>kunitoriMapStorage);
 await page.waitForFunction(()=>document.querySelector('progress')?.value>0);
 assert.equal(await page.evaluate(()=>window.started),false);
 await page.evaluate(()=>localStorage.setItem('kunitori.nara.v1','saved-game'));
 await context.setOffline(true);
 await page.waitForTimeout(700);
 const partial=(await cursor(page)).next;assert(partial>=20 && partial<100);
 await context.setOffline(false);
 await page.reload();await page.evaluate(()=>kunitoriMapStorage);await page.waitForFunction(()=>window.started,{},{timeout:30000});
 assert.equal((await cursor(page)).next,100);assert(peak<=2);
 assert.equal(await page.evaluate(()=>localStorage.getItem('kunitori.nara.v1')),'saved-game');
 const packs=fixture().manifest.packs;
 assert.equal(requests.get(packs[0][0]),1);assert.equal(requests.get(packs[1][0]),1);
 assert(requests.get(packs[2][0])>=2);assert(requests.get(packs[3][0])>=2);
 assert.equal(await context.serviceWorkers()[0].evaluate(()=>self.packDiskReads||0),0,'Initial download must stream, not fill memory');
 assert.equal(await page.evaluate(()=>kunitoriMapMemory.get()),32,'New installations default to 32 MB');
 for(const size of [32,64,128,256])assert.equal(await page.evaluate(size=>kunitoriMapMemory.set(size),size),size);
 assert.equal(await page.evaluate(()=>kunitoriMapMemory.get()),256);
 await assert.rejects(page.evaluate(()=>kunitoriMapMemory.set(8)),/Invalid/);
 const counts=new Map(requests);
 await context.setOffline(true);
 const decoded=await page.evaluate(async paths=>Promise.all(paths.map(async path=>{
 const response=await fetch(path);return Array.from(new Uint8Array(await response.arrayBuffer()));
 })),assets.map(entry=>entry[0]));
 decoded.forEach((bytes,i)=>assert.deepEqual(Buffer.from(bytes),assets[i][1]));
 assert.deepEqual(requests,counts);
 assert.equal(await context.serviceWorkers()[0].evaluate(()=>self.packDiskReads),10,'100 concurrent image requests must read each of 10 packs only once');
 const beforeRepeat=await context.serviceWorkers()[0].evaluate(()=>self.packDiskReads);
 await page.evaluate(async paths=>{for(const path of paths)await (await fetch(path)).arrayBuffer();},assets.map(entry=>entry[0]));
 assert.equal(await context.serviceWorkers()[0].evaluate(()=>self.packDiskReads),beforeRepeat,'Repeated visible images must reuse compressed memory');
 await context.setOffline(false);
 // A content update only transfers the one changed pack.
 assets[95][1]=Buffer.alloc(4096,201);version=2;
 await page.reload();await page.evaluate(()=>kunitoriMapStorage);await page.waitForFunction(()=>window.started,{},{timeout:30000});
 assert.equal(await page.evaluate(()=>kunitoriMapMemory.get()),256,'Selection survives worker upgrade and old-version cleanup');
 await page.evaluate(()=>kunitoriMapMemory.set(32));
 for (const pack of fixture().manifest.packs.slice(0,9))assert.equal(requests.get(pack[0]),counts.get(pack[0]));
 await context.close();
 // Migrate an interrupted old individual-image download without fetching its prefix.
 context=await browser.newContext();page=await context.newPage();
 await page.goto(base+'seed'); // Same origin, no loader.
 const legacy=fixture().manifest.assets.slice(0,20);
 await page.evaluate(async ({entries,base,version})=>{
  const store=await caches.open('kunitori-map-images-v1');
  for(let i=0;i<entries.length;i++)await store.put(new URL(entries[i][0]+'?map-sha256='+entries[i][1],base),new Response(new Uint8Array(4096).fill(i)));
  const meta=await caches.open('kunitori-map-images-meta-v1');await meta.put(new URL('__map_progress__/'+version,base),new Response(JSON.stringify({next:20})));
  localStorage.setItem('kunitori.nara.v1','legacy-save');
 },{entries:legacy,base,version});
 const before=new Map(requests);
 await page.goto(base);await page.evaluate(()=>kunitoriMapStorage);await page.waitForFunction(()=>window.started,{},{timeout:30000});
 for(const pack of fixture().manifest.packs.slice(0,2))assert.equal(requests.get(pack[0]),before.get(pack[0]),'Existing prefix must not download again');
 await context.setOffline(true);
 assert.equal(await page.evaluate(async path=>new Uint8Array(await (await fetch(path)).arrayBuffer())[0],assets[10][0]),10);
 assert.equal(await page.evaluate(()=>localStorage.getItem('kunitori.nara.v1')),'legacy-save');
 assert.equal((await cursor(page)).legacy,20);
 console.log('PASS: packed download/resume; checksums; two bounded transfers; offline byte-exact images; legacy prefix/save migration; delta pack reuse.');
 await browser.close();await new Promise(resolve=>server.close(resolve));
})().catch(async error=>{console.error(error);if(browser)await browser.close();server.close();process.exitCode=1;});

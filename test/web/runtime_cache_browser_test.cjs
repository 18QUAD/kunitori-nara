// Real service worker: cached geometry/code works offline; interrupted gzip chunks resume.
const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),crypto=require('node:crypto'),zlib=require('node:zlib');
const assert=require('node:assert/strict');
const root='/game/';
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const text=Buffer.from(JSON.stringify({towns:Array.from({length:200},(_,i)=>({id:'24'+i,population:i}))}));
const wasm=Buffer.from([0,97,115,109,1,0,0,0]);
const source=Buffer.from('window.offlineCodeLoaded=true;');
const runtimeFiles=[['assets/assets/data/prefectures/24.json',text,'application/json'],['canvaskit/canvaskit.wasm',wasm,'application/wasm'],['main.dart.js',source,'text/javascript']];
const chunks=[],files=[],contents=new Map();
for(const [path,bytes,mime] of runtimeFiles){
 const packed=zlib.gzipSync(bytes);const ids=[];
 for(let start=0;start<packed.length;start+=200){const b=packed.subarray(start,start+200),name='runtime-data/'+sha(b)+'.bin';ids.push(chunks.length);chunks.push([name,sha(b),b.length]);contents.set(name,b);}
 files.push({path,mime,bytes:bytes.length,chunks:ids,sha256:sha(bytes)});
}
const runtime={schema:1,revision:'runtime-test',bytes:chunks.reduce((n,c)=>n+c[2],0),chunks,files};
const image={schema:1,revision:'images-test',bytes:0,assets:[]};
const worker=(fs.readFileSync('web/vendor/fast-sha256.js','utf8')+fs.readFileSync('web/map-cache-worker.js','utf8')).replace('__MAP_IMAGE_REVISION__','images-test').replace('__RUNTIME_DATA_REVISION__','runtime-test');
let requests=new Map(),fail=true;let browser;
const server=http.createServer((req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname.slice(root.length);
 res.setHeader('Cache-Control','no-store');
 if(path==='') {res.setHeader('Content-Type','text/html');res.end(`<div id="app-host"></div><script src="map-cache.js?v=runtime-test"></script><script>kunitoriMapDownload.then(()=>window.started=true)</script>`);}
 else if(path==='map-cache.js'){res.setHeader('Content-Type','text/javascript');res.end(fs.readFileSync('web/map-cache.js'));}
 else if(path==='map-cache-worker.js'){res.setHeader('Content-Type','text/javascript');res.end(worker);}
 else if(path==='map-image-manifest.json')res.end(JSON.stringify(image));
 else if(path==='runtime-data-manifest.json')res.end(JSON.stringify(runtime));
 else if(contents.has(path)){
  requests.set(path,(requests.get(path)||0)+1);
  if(fail&&path===chunks[2][0]){fail=false;res.writeHead(503);res.end();}
  else setTimeout(()=>res.end(contents.get(path)),30);
 }else{res.writeHead(404);res.end('Raw runtime URLs do not exist');}
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base=`http://127.0.0.1:${server.address().port}${root}`;
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
 const context=await browser.newContext();const page=await context.newPage();
 await page.goto(base);await page.waitForFunction(()=>window.started===true,{timeout:30000});
 assert.equal(requests.get(chunks[0][0]),1,'Successful chunks reused after a failed batch');
 assert.equal(requests.get(chunks[2][0]),2,'Failed chunk retried automatically');
 await context.setOffline(true);
 const result=await page.evaluate(async()=>{
  const json=await (await fetch('assets/assets/data/prefectures/24.json?coast=version')).json();
  const response=await fetch('canvaskit/canvaskit.wasm');
  await WebAssembly.instantiateStreaming(Promise.resolve(response));
  await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='main.dart.js?v=build';s.onload=resolve;s.onerror=reject;document.body.append(s);});
  return {towns:json.towns.length,code:window.offlineCodeLoaded};
 });
 assert.deepEqual(result,{towns:200,code:true});
 assert.equal(requests.size,chunks.length);
 console.log('PASS: all runtime chunks saved before start; automatic retry/resume; offline versioned geometry, streamed gzip, JS and WASM; raw URLs absent.');
 await browser.close();server.close();
})().catch(async error=>{console.error(error);if(browser)await browser.close();server.close();process.exitCode=1;});

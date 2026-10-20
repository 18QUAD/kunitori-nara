// A stale cached shell must never start old code against a new worker/data set.
const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),crypto=require('node:crypto'),zlib=require('node:zlib');
const assert=require('node:assert/strict');
const build='coherent-2', root='/game/';
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const pageHtml=version=>`<div id="app-host"></div><script src="diagnostics.js?v=${version}"></script><script src="map-cache.js?v=${version}"></script><script>kunitoriMapDownload.then(()=>{let s=document.createElement('script');s.src='main.dart.js?v=${version}';document.body.append(s)})</script>`;
const cacheSource=fs.readFileSync('web/map-cache.js');
const contents=new Map(),chunks=[],files=[];
for(const [path,source,mime] of [
 ['index.html',pageHtml(build),'text/html'],
 ['diagnostics.js',`window.shellBuild='${build}';`,'text/javascript'],
 ['map-cache.js',cacheSource,'text/javascript'],
 ['main.dart.js',`window.startedBuild='${build}';window.startedShell=window.shellBuild;`,'text/javascript'],
]){
 const bytes=Buffer.from(source),packed=zlib.gzipSync(bytes),name='runtime-data/'+sha(packed)+'.bin';
 files.push({path,mime,bytes:bytes.length,chunks:[chunks.length],sha256:sha(bytes)});
 chunks.push([name,sha(packed),packed.length]);contents.set(name,packed);
}
const runtime={schema:1,revision:'runtime-coherent-2',bytes:chunks.reduce((n,c)=>n+c[2],0),chunks,files};
const images={schema:1,revision:'no-images',bytes:0,assets:[]};
const worker=(fs.readFileSync('web/vendor/fast-sha256.js','utf8')+fs.readFileSync('web/map-cache-worker.js','utf8'))
 .replace('__MAP_IMAGE_REVISION__',images.revision).replace('__RUNTIME_DATA_REVISION__',runtime.revision).replace('__APP_BUILD__',build);
let browser,starts=0;const requests=[];
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://localhost'),name=url.pathname.slice(root.length);requests.push(req.url);
 res.setHeader('Cache-Control','public, max-age=86400');
 if(name===''||name==='index.html'){res.setHeader('Content-Type','text/html');res.end(pageHtml('stale-1'));}
 else if(name==='diagnostics.js'){res.setHeader('Content-Type','text/javascript');res.end("window.shellBuild='stale-1';");}
 else if(name==='map-cache.js'){res.setHeader('Content-Type','text/javascript');res.end(cacheSource);}
 else if(name==='map-cache-worker.js'){res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','text/javascript');res.end(worker);}
 else if(name==='runtime-data-manifest.json')res.end(JSON.stringify(runtime));
 else if(name==='map-image-manifest.json')res.end(JSON.stringify(images));
 else if(contents.has(name))res.end(contents.get(name));
 else if(name==='main.dart.js'){res.setHeader('Content-Type','text/javascript');res.end("window.startedBuild='stale-1';");}
 else {res.writeHead(404);res.end();}
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});
 const context=await browser.newContext();const page=await context.newPage();
 await context.addInitScript(()=>{
  if(!localStorage.seeded){localStorage.setItem('flutter.kunitori.nara.v1','existing-game');localStorage.setItem('flutter.kunitori.nara.mapView.v1','existing-view');localStorage.seeded='1';}
 });
 page.on('framenavigated',f=>{if(f===page.mainFrame())starts++;});
 await page.goto(`http://127.0.0.1:${server.address().port}${root}`);
 await page.waitForFunction(()=>window.startedBuild==='coherent-2',{},{timeout:30000});
 assert.equal(await page.evaluate(()=>window.startedShell),build,'Old diagnostic code must also be replaced');
 assert.equal(starts,2,'Exactly one correction before starting, no reload loop');
 assert(!requests.some(u=>u.includes('main.dart.js')),'Executable must come from the verified runtime, not stale HTTP cache');
 assert.equal(new URL(page.url()).searchParams.get('app-build'),build);
 await context.setOffline(true);await page.reload();
 await page.waitForFunction(()=>window.startedBuild==='coherent-2',{},{timeout:30000});
 assert.equal(starts,3,'Offline restart must not add a correction reload');
 assert.deepEqual(await page.evaluate(()=>[localStorage.getItem('flutter.kunitori.nara.v1'),localStorage.getItem('flutter.kunitori.nara.mapView.v1')]),['existing-game','existing-view']);
 console.log('PASS: stale HTML/JS cache corrected before engine start; matching runtime and diagnostics; one correction, offline restart, saves preserved.');
 await browser.close();server.close();
})().catch(async e=>{console.error(e);if(browser)await browser.close();server.close();process.exitCode=1;});

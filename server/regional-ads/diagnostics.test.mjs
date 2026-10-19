import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {sanitizeReport,handleDiagnostics,DiagnosticsStore} from './diagnostics.mjs';
const sample = () => ({clientId:'client-123456789012345', sessions:[{id:'run-1',userAgent:'iPhone test',events:[{
  event:'conquest_before',at:'2026-10-19T00:00:00Z',state:{prefecture:'24',totalTaps:512,save:'DO NOT STORE',error:'failed https://example.com/?token=secret'},memory:{canvasKitHeapBytes:67108864},
}]}],save:'DO NOT STORE'});
function store() {
  const db=new DatabaseSync(':memory:');let alarm;
  const ctx={storage:{sql:{exec(sql,...params){const rows=db.prepare(sql).all(...params);return {toArray:()=>rows};}},async setAlarm(at){alarm=at;}}};
  return {store:new DiagnosticsStore(ctx),db,alarm:()=>alarm};
}
const post = (body,origin='https://18quad.github.io')=>new Request('https://worker.example/diagnostics',{method:'POST',headers:{Origin:origin},body:JSON.stringify(body)});
const envFor = backend => ({DIAGNOSTICS_READ_TOKEN:'private-test-token',DIAGNOSTICS:{idFromName:()=>1,get:()=>backend}});
test('sanitize allowlist never stores saves or arbitrary fields',()=>{
  const r=sanitizeReport(sample());assert(!JSON.stringify(r).includes('DO NOT STORE'));assert(!JSON.stringify(r).includes('token=secret'));
  assert.equal(r.sessions[0].events[0].memory.processBytes,null);assert.equal(sanitizeReport({}),null);
});
test('download progress counters survive private report sanitization',()=>{
  const report=sample();
  const counters={mapCacheLimitMb:256,mapCacheBytes:12345678,mapDownloadSaved:480,mapDownloadTotal:44400,mapDownloadBytes:1234567,mapDownloadTotalBytes:302822453};
  Object.assign(report.sessions[0].events[0].state,counters);
  const state=sanitizeReport(report).sessions[0].events[0].state;
  for(const [key,value] of Object.entries(counters))assert.equal(state[key],value);
  assert.equal(state.save,undefined);
});
test('origin, method, size checks and authenticated read',async()=>{
  const {store:backend}=store(),env=envFor(backend);
  assert.equal((await handleDiagnostics(post(sample(),'https://evil.test'),env)).status,403);
  assert.equal((await handleDiagnostics(post({...sample(),filler:'x'.repeat(50000)}),env)).status,400);
  assert.equal((await handleDiagnostics(new Request('https://worker.example/diagnostics/reports'),env)).status,401);
  assert.equal((await handleDiagnostics(post(sample()),env)).status,200);
  assert.equal((await handleDiagnostics(post(sample()),env)).status,429);
  const r=await handleDiagnostics(new Request('https://worker.example/diagnostics/reports?platform=ios',{
    headers:{Authorization:'Bearer private-test-token'}}),env);
  assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal((await r.json()).reports.length,1);
});
test('bounded 128 clients, expiry alarm and iOS filter',async()=>{
  const {store:backend,db,alarm}=store();
  for(let i=0;i<140;i++)db.prepare('INSERT INTO reports VALUES (?,?,?)').run('client-'+i,Date.now()-i*1000,JSON.stringify({...sample(),clientId:'client-'+i}));
  backend.prune(Date.now());assert.equal(db.prepare('SELECT COUNT(*) AS n FROM reports').get().n,128);
  db.prepare('INSERT INTO reports VALUES (?,?,?)').run('expired',0,JSON.stringify(sample()));
  await backend.alarm();assert(!db.prepare('SELECT client FROM reports WHERE client=?').get('expired'));assert(alarm()>Date.now());
  const r=await backend.fetch(new Request('https://internal/reports?limit=2&platform=ios'));assert.equal((await r.json()).reports.length,2);
});

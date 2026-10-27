'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(process.argv[2] || 'web/map-cache.js','utf8');
const connect=source.slice(source.indexOf('  async function connect()'),source.indexOf('  function resume()'));
async function startup(done) {
 let reply;
 const status=new Promise(resolve=>{reply=resolve;});
 const timers=[];const reports=[];
 const root=new URL('https://example.com/game/');const worker=new URL('map-cache-worker.js?v=1',root);
 const context=vm.createContext({URL,running:false,lastProgress:undefined,connecting:false,connected:false,done:false,panel:null,setupAttempts:0,setupTimer:undefined,root,worker,version:'1',retry:1000,
  clearTimeout(){},setTimeout:(fn,delay)=>{timers.push({fn,delay});},
  record(){},showProgress:result=>reports.push(result),checkpoint(){},finishMapDownload(){},next(){},
  controlled:()=>true,bounded:x=>x,
  window:{},navigator:{onLine:true,serviceWorker:{getRegistration:async()=>({active:{scriptURL:worker.href}})}},
  request:async(type)=>type==='map-runtime-version' ? {build:'1'} : status,
 });
 vm.runInContext(connect,context);
 const pending=context.connect();
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(timers.length,0,'must not start warm-up while stored progress is unresolved');
 reply({done,saved:done?100:50,total:100,savedBytes:done?100:50,bytes:100});
 await pending;
 return {context,timers,reports};
}
test('completed disk store finishes startup without scheduling warm-up',async()=>{
 const {context,timers,reports}=await startup(true);assert.equal(context.done,true);assert.equal(timers.length,0);assert.equal(reports[0].saved,100);
});
test('partial disk store is reported before scheduling resumed warm-up',async()=>{
 const {context,timers,reports}=await startup(false);assert.equal(context.done,false);assert.equal(reports[0].saved,50);assert.equal(timers.length,1);
});

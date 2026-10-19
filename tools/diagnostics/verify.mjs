import fs from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
const config=JSON.parse(fs.readFileSync('../../assets/data/affiliate_config.json'));
const endpoint=new URL('/diagnostics',config.endpoint);
const clientId='verification-'+randomUUID();
const session={id:'ci-'+randomUUID(),build:'integration-check',userAgent:'DiagnosticsIntegrationTest',events:[{
  event:'verification',at:new Date().toISOString(),state:{prefecture:'29'},memory:{processBytes:null},
}]};
const post=await fetch(endpoint,{method:'POST',headers:{Origin:'https://18quad.github.io','Content-Type':'text/plain'},
  body:JSON.stringify({clientId,sessions:[session]}),signal:AbortSignal.timeout(30000)});
if(!post.ok)throw Error(`Diagnostic upload HTTP ${post.status}`);
const read=new URL('/diagnostics/reports',endpoint);
const denied=await fetch(read,{signal:AbortSignal.timeout(30000)});
if(denied.status!==401)throw Error('Private diagnostics read did not require authentication');
const token=createHash('sha256').update('kunitori-diagnostics-read-v1\0'+process.env.CLOUDFLARE_API_TOKEN).digest('hex');
const response=await fetch(read,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(30000)});
if(!response.ok)throw Error(`Diagnostic authenticated read HTTP ${response.status}`);
const payload=await response.json();
if(!payload.reports.some(r=>r.clientId===clientId && r.sessions.some(s=>s.events.some(e=>e.event==='verification'))))throw Error('Uploaded verification not found');
console.log('PASS: deployed upload, durable persistence, unauthorized read rejection and authenticated retrieval. No user logs printed.');

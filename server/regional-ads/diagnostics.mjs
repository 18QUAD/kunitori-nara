const ORIGIN = 'https://18quad.github.io';
const MAX_BYTES = 48 * 1024;
const RETENTION = 7 * 24 * 60 * 60 * 1000;
const fields = new Set(['map','prefecture','city','selected','scale','centerX','centerY',
  'terrain','changingMap','totalTaps','territories','attackTarget','flutterImageBytes',
  'flutterImageCount','flutterLiveImages','flutterPendingImages','backgroundCache',
  'borderCache','destinationPrefecture','imageScale','imageCache','persisted','error']);
function scalar(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'boolean' || value == null) return value;
  return typeof value === 'string' ? value.slice(0,240).replace(/https?:\/\/\S+/g,'[url]') : null;
}
function snapshot(value) {
  const result = {};
  if (!value || typeof value !== 'object') return result;
  for (const [key,item] of Object.entries(value)) {
    if (!fields.has(key)) continue;
    if (['backgroundCache','borderCache','imageCache'].includes(key)) {
      result[key] = Object.fromEntries(['images','decoding','queued','owners'].map(k=>[k,
        typeof item?.[k] === 'number' ? scalar(item[k]) : null]));
    } else result[key] = scalar(item);
  }
  return result;
}
export function sanitizeReport(input) {
  if (!/^[a-zA-Z0-9-]{16,80}$/.test(input?.clientId || '') || !Array.isArray(input?.sessions)) return null;
  const sessions = input.sessions.slice(-3).filter(s => /^[a-zA-Z0-9-]{1,80}$/.test(s?.id || '') && Array.isArray(s.events)).map(s=>({
    id:s.id, build:scalar(s.build), startedAt:scalar(s.startedAt), navigation:scalar(s.navigation),
    userAgent:scalar(s.userAgent), ended:s.ended === true, wasDiscarded:s.wasDiscarded === true,
    previousSession:scalar(s.previousSession), previousEnd:scalar(s.previousEnd),
    events:s.events.slice(-64).map(e=>({at:scalar(e?.at),event:scalar(e?.event),
      visibility:scalar(e?.visibility),state:snapshot(e?.state),
      memory:Object.fromEntries(['jsUsedBytes','jsTotalBytes','jsLimitBytes','canvasKitHeapBytes','processBytes'].map(k=>[k,
        typeof e?.memory?.[k] === 'number' ? scalar(e.memory[k]) : null])),
    })),
  }));
  return sessions.length ? {version:1,clientId:input.clientId,sessions} : null;
}
export async function boundedJson(request) {
  if (Number(request.headers.get('Content-Length')) > MAX_BYTES) return null;
  const reader=request.body?.getReader();if(!reader)return null;
  const chunks=[];let bytes=0;
  try {
    for (;;) {const {done,value}=await reader.read();if(done)break;
      bytes+=value.byteLength;if(bytes>MAX_BYTES){await reader.cancel();return null;}chunks.push(value);}
    const body=new Uint8Array(bytes);let offset=0;for(const c of chunks){body.set(c,offset);offset+=c.byteLength;}
    return JSON.parse(new TextDecoder().decode(body));
  } catch {return null;}
}
export async function handleDiagnostics(request, env) {
  const url=new URL(request.url), allowed=env.ALLOWED_ORIGIN || ORIGIN;
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',
    'Access-Control-Allow-Origin':allowed,'Access-Control-Allow-Methods':'POST, OPTIONS',
    'Access-Control-Allow-Headers':'Content-Type','X-Content-Type-Options':'nosniff'};
  const reply=(body,status=200)=>Response.json(body,{status,headers});
  if(!env.DIAGNOSTICS)return reply({error:'not_configured'},503);
  if(url.pathname==='/diagnostics/reports') {
    if(request.method!=='GET')return reply({error:'method_not_allowed'},405);
    const supplied=request.headers.get('Authorization') || '';
    if(!env.DIAGNOSTICS_READ_TOKEN || supplied !== `Bearer ${env.DIAGNOSTICS_READ_TOKEN}`)return reply({error:'unauthorized'},401);
    const internal=new URL('https://diagnostics.internal/reports');
    internal.searchParams.set('limit',String(Math.min(5,Math.max(1,Number(url.searchParams.get('limit')) || 5))));
    if(url.searchParams.get('platform')==='ios')internal.searchParams.set('platform','ios');
    return env.DIAGNOSTICS.get(env.DIAGNOSTICS.idFromName('reports-v1')).fetch(new Request(internal));
  }
  if(url.pathname!=='/diagnostics')return reply({error:'not_found'},404);
  if(request.headers.get('Origin')!==allowed)return reply({error:'origin_not_allowed'},403);
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return reply({error:'method_not_allowed'},405);
  const clean=sanitizeReport(await boundedJson(request));
  if(!clean || JSON.stringify(clean).length>MAX_BYTES)return reply({error:'invalid_report'},400);
  const result=await env.DIAGNOSTICS.get(env.DIAGNOSTICS.idFromName('reports-v1')).fetch(new Request('https://diagnostics.internal/ingest',{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(clean),
  }));
  return reply(await result.json(),result.status);
}

// A bounded, private SQLite store. No public list/read route; no IP addresses or saves.
export class DiagnosticsStore {
  constructor(ctx) {
    this.ctx=ctx;this.sql=ctx.storage.sql;
    this.sql.exec('CREATE TABLE IF NOT EXISTS reports (client TEXT PRIMARY KEY, updated INTEGER NOT NULL, payload TEXT NOT NULL)');
    this.window=0;this.requests=0;
  }
  prune(now) {
    this.sql.exec('DELETE FROM reports WHERE updated < ?',now-RETENTION);
    this.sql.exec('DELETE FROM reports WHERE client IN (SELECT client FROM reports ORDER BY updated DESC LIMIT -1 OFFSET 128)');
  }
  async fetch(request) {
    const now=Date.now(),url=new URL(request.url);this.prune(now);
    if(url.pathname==='/reports') {
      const limit=Math.min(5,Math.max(1,Number(url.searchParams.get('limit')) || 5));
      const rows=this.sql.exec('SELECT payload, updated FROM reports ORDER BY updated DESC LIMIT 128').toArray();
      const reports=rows.map(r=>({...JSON.parse(r.payload),receivedAt:new Date(r.updated).toISOString()}))
        .filter(r=>url.searchParams.get('platform')!=='ios' || r.sessions.some(s=>/iPhone|iPad|iPod/.test(s.userAgent || ''))).slice(0,limit);
      return Response.json({version:1,retentionDays:7,reports},{headers:{'Cache-Control':'no-store'}});
    }
    if(url.pathname!=='/ingest'||request.method!=='POST')return Response.json({error:'not_found'},{status:404});
    if(now-this.window>60000){this.window=now;this.requests=0;}
    if(++this.requests>120)return Response.json({error:'rate_limited'},{status:429});
    const report=sanitizeReport(await boundedJson(request));
    if(!report)return Response.json({error:'invalid_report'},{status:400});
    const old=this.sql.exec('SELECT updated FROM reports WHERE client = ?',report.clientId).toArray()[0];
    if(old && now-old.updated<5000)return Response.json({error:'rate_limited'},{status:429});
    this.sql.exec('INSERT INTO reports (client,updated,payload) VALUES (?,?,?) ON CONFLICT(client) DO UPDATE SET updated=excluded.updated,payload=excluded.payload',report.clientId,now,JSON.stringify(report));
    this.prune(now);await this.scheduleAlarm(now);
    return Response.json({ok:true});
  }
  async scheduleAlarm(now) {
    const row=this.sql.exec('SELECT MIN(updated) AS oldest FROM reports').toArray()[0];
    if(row?.oldest!=null)await this.ctx.storage.setAlarm(Math.max(now+1000,row.oldest+RETENTION));
  }
  async alarm(){const now=Date.now();this.prune(now);await this.scheduleAlarm(now);}
}

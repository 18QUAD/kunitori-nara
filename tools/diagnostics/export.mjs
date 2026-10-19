// Run only in the authenticated Actions job. Plain logs and service credentials
// never enter public job output or artifacts; only an encrypted check result does.
import fs from 'node:fs';
import {createHash,randomBytes,createCipheriv,publicEncrypt,constants} from 'node:crypto';
import {brotliCompressSync} from 'node:zlib';
const publicKey=process.env.DIAGNOSTICS_PUBLIC_KEY;
if(!publicKey || !/^[A-Za-z0-9+/=]{300,1200}$/.test(publicKey))throw Error('Invalid export public key');
const token=createHash('sha256').update('kunitori-diagnostics-read-v1\0'+process.env.CLOUDFLARE_API_TOKEN).digest('hex');
const config=JSON.parse(fs.readFileSync('assets/data/affiliate_config.json'));
const url=new URL('/diagnostics/reports',config.endpoint);
url.searchParams.set('limit','5');if(process.env.DIAGNOSTICS_PLATFORM==='ios')url.searchParams.set('platform','ios');
const response=await fetch(url,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(30000)});
if(!response.ok)throw Error(`Diagnostic retrieval HTTP ${response.status}`);
const report=await response.json();
let envelope;
for(;;){
  const key=randomBytes(32),iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);
  const compressed=brotliCompressSync(Buffer.from(JSON.stringify(report)));
  const ciphertext=Buffer.concat([cipher.update(compressed),cipher.final()]);
  const wrapped=publicEncrypt({key:Buffer.from(publicKey,'base64'),format:'der',type:'spki',
    padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key);
  envelope=JSON.stringify({v:1,key:wrapped.toString('base64'),iv:iv.toString('base64'),
    tag:cipher.getAuthTag().toString('base64'),data:ciphertext.toString('base64')});
  if(envelope.length<60000)break;
  if(!report.reports?.length)throw Error('Export exceeds check output budget');
  report.reports.pop();
}
const result=await fetch(`https://api.github.com/repos/${process.env.GITHUB_REPOSITORY}/check-runs`,{
  method:'POST',headers:{Authorization:`Bearer ${process.env.GH_TOKEN}`,
    Accept:'application/vnd.github+json','Content-Type':'application/json'},
  body:JSON.stringify({name:'diagnostics-export',head_sha:process.env.GITHUB_SHA,
    external_id:process.env.DIAGNOSTICS_REQUEST_ID,status:'completed',conclusion:'success',
    output:{title:'Encrypted diagnostics export',summary:envelope}}),
});
if(!result.ok)throw Error(`Encrypted check write HTTP ${result.status}`);
console.log(`Encrypted export ready: ${report.reports?.length || 0} report(s). No plaintext logs published.`);

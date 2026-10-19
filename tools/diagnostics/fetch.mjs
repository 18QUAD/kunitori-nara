// Fetch private server diagnostics through the existing credentialed admin job.
// The local private key never leaves this process. Only ciphertext is visible on GitHub.
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync,randomUUID,privateDecrypt,createDecipheriv,constants} from 'node:crypto';
import {brotliDecompressSync} from 'node:zlib';
import fs from 'node:fs';
const repo='18QUAD/kunitori-nara',branch=process.env.DIAGNOSTICS_REF || 'wip/nationwide-20261015';
const output=process.argv[2] || '/workspace/remote-diagnostics.json';
const gh=(...args)=>execFileSync('gh',args,{encoding:'utf8',stdio:['ignore','pipe','pipe']});
const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const requestId=randomUUID(),publicDer=publicKey.export({format:'der',type:'spki'}).toString('base64');
gh('workflow','run','regional-ads.yml','--repo',repo,'--ref',branch,
  '-f','operation=export','-f',`public_key=${publicDer}`,'-f',`request_id=${requestId}`,
  '-f',`platform=${process.env.DIAGNOSTICS_PLATFORM || 'ios'}`);
const head=JSON.parse(gh('api',`repos/${repo}/branches/${branch.replaceAll('/','%2F')}`)).commit.sha;
const deadline=Date.now()+8*60*1000;
console.log('Requested authenticated diagnostics export.');
while(Date.now()<deadline){
  const checks=JSON.parse(gh('api',`repos/${repo}/commits/${head}/check-runs?check_name=diagnostics-export&per_page=100`));
  const check=checks.check_runs?.find(c=>c.external_id===requestId);
  if(check){
    const e=JSON.parse(check.output.summary);
    const key=privateDecrypt({key:privateKey,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(e.key,'base64'));
    const cipher=createDecipheriv('aes-256-gcm',key,Buffer.from(e.iv,'base64'));cipher.setAuthTag(Buffer.from(e.tag,'base64'));
    const plain=brotliDecompressSync(Buffer.concat([cipher.update(Buffer.from(e.data,'base64')),cipher.final()]));
    const report=JSON.parse(plain.toString());
    fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{mode:0o600});
    console.log(`Saved ${report.reports?.length || 0} report(s) to ${output}`);process.exit(0);
  }
  await new Promise(resolve=>setTimeout(resolve,10000));
}
throw Error('Diagnostic export timed out; inspect the admin workflow status.');

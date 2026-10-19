import assert from 'node:assert/strict';
import {generateKeyPairSync,privateDecrypt,createDecipheriv,constants} from 'node:crypto';
import {brotliDecompressSync} from 'node:zlib';
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
process.env.DIAGNOSTICS_PUBLIC_KEY=publicKey.export({type:'spki',format:'der'}).toString('base64');
process.env.CLOUDFLARE_API_TOKEN='test-cloudflare-credential';
process.env.GITHUB_REPOSITORY='18QUAD/kunitori-nara';process.env.GITHUB_SHA='test-sha';
process.env.GH_TOKEN='test-gh-credential';process.env.DIAGNOSTICS_REQUEST_ID='test-request';
const plaintext={version:1,reports:[{clientId:'test-client-only',sessions:[{events:[{event:'conquest_before'}]}]}]};
let check;
globalThis.fetch=async (url,options)=>{
  if(new URL(url).pathname==='/diagnostics/reports') {
    assert(options.headers.Authorization.startsWith('Bearer '));
    return {ok:true,json:async()=>plaintext};
  }
  assert.equal(new URL(url).hostname,'api.github.com');
  check=JSON.parse(options.body);return {ok:true};
};
await import('../../tools/diagnostics/export.mjs');
const raw=JSON.stringify(check);assert(!raw.includes('test-client-only'));assert(!raw.includes('test-cloudflare-credential'));
assert.equal(check.external_id,'test-request');
const e=JSON.parse(check.output.summary);
const key=privateDecrypt({key:privateKey,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(e.key,'base64'));
const decipher=createDecipheriv('aes-256-gcm',key,Buffer.from(e.iv,'base64'));decipher.setAuthTag(Buffer.from(e.tag,'base64'));
const plain=brotliDecompressSync(Buffer.concat([decipher.update(Buffer.from(e.data,'base64')),decipher.final()]));
assert.deepEqual(JSON.parse(plain),plaintext);
console.log('PASS: authenticated export encrypts all report contents; only the requesting local key decrypts them.');

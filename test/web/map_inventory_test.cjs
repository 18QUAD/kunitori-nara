const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
test('all 417k image entries use exact numeric identities without retained filename maps',async()=>{
 const manifest=fs.readFileSync('data/prepared_maps/map-image-manifest.json');
 const expected=JSON.parse(manifest),revision=expected.revision;
 const context=vm.createContext({URL,Response,TextDecoder,
  self:{location:{href:'https://test.invalid/game/map-cache-worker.js'},addEventListener(){}},
  caches:{open:async()=>({match:async()=>new Response(manifest)})}});
 vm.runInContext(fs.readFileSync('web/map-cache-worker.js','utf8').replace('__MAP_IMAGE_REVISION__',revision)+
  '\nglobalThis.read=inventory;globalThis.entry=assetEntry;globalThis.find=findAsset;globalThis.code=tileCode;',context);
 const data=await context.read();
 assert.equal(data.assetCount,expected.assets.length);
 assert.equal(data.names,undefined);assert.equal(data.byPath,undefined);assert.equal(data.assets,undefined);
 assert.equal(data.codes.byteLength+data.sortedIndices.byteLength+data.locations.byteLength+data.byteOffsets.byteLength,expected.assets.length*28+8);
 let cursor=0;
 for(let p=0;p<expected.packs.length;p++){
  const pack=expected.packs[p];let offset=0;
  for(let i=pack[3];i<pack[4];i++){
   const [name,length]=expected.assets[i],actual=context.entry(data,i);
   assert.deepEqual(Array.from(actual),[expected.assetPrefix+name,null,length,p,offset,i]);
   assert.deepEqual(Array.from(context.find(data,'/game/'+actual[0])),Array.from(actual));
   assert.equal(data.byteOffsets[i],cursor);offset+=length;cursor+=length;
  }
  assert.equal(offset,pack[2]);
 }
 assert.equal(cursor,expected.bytes);assert.equal(data.byteOffsets.at(-1),cursor);
 for(const bad of ['8_4096_0_town.webp','8_0_2048_town.webp','8_00_0_town.webp','-4_0_0_pref.webp','0_0_0_unknown.webp','../0_0_0_town.webp'])assert.equal(context.find(data,'/game/'+expected.assetPrefix+bad),undefined);
 // A missing but valid numeric key must never return its sorted neighbor.
 const names=new Set(expected.assets.map(a=>a[0]));
 for(const name of ['8_4095_2047_town.webp','0_0_0_background.webp'])if(!names.has(name))assert.equal(context.find(data,'/game/'+expected.assetPrefix+name),undefined);
});

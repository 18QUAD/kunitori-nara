/* Compressed map bytes live on disk, independently of Flutter/GPU image caches. */
'use strict';
const REVISION = '__MAP_IMAGE_REVISION__';
const ROOT = new URL('./', self.location.href);
const STORE = 'kunitori-map-images-v1';
const PACK_STORE = 'kunitori-map-packs-v1';
const META = 'kunitori-map-images-meta-v1';
const BATCH = 48;
const CONCURRENCY = 2;
// Initial packs stream directly to disk, before the rendering engine starts.
// Refill each of eight slots independently instead of waiting for a slow partner.
// Packs are <= 1 MiB; there are no decoded images or retained download buffers.
const DOWNLOAD_CONCURRENCY = 8;
const DOWNLOAD_WINDOW_MS = 1200;
const DOWNLOAD_WINDOW_PACKS = 32;
let inventoryPromise;
let warming;
const transfers = new Map();
const keyFor = entry => new URL(`${entry[0]}?map-sha256=${entry[1]}`, ROOT).href;
const progressKey = new URL(`__map_progress__/${REVISION}`, ROOT).href;

async function inventory() {
  if (!inventoryPromise) {
    inventoryPromise = (async () => {
      const meta = await caches.open(META);
      const url = new URL(`map-image-manifest.json?packs=1&v=${REVISION}`, ROOT).href;
      let response = await meta.match(url);
      let value;
      if (!response) {
        response = await fetch(url, {cache: 'no-cache'});
        if (!response.ok) throw new Error(`Map inventory HTTP ${response.status}`);
        // Validate before persisting; a deployment can briefly serve mixed files.
        const bytes = await response.arrayBuffer();
        value = JSON.parse(new TextDecoder().decode(bytes));
        if (value.schema !== 1 || value.revision !== REVISION) throw new Error('Map inventory version mismatch');
        await meta.put(url, new Response(bytes, {headers: {'Content-Type': 'application/json'}}));
      } else {
        value = await response.json();
      }
      const assetCount = value.assets.length;
      const byteOffsets = new Float64Array(assetCount + 1);
      if (value.packSchema === 2) {
        // Keep one short name plus typed offsets per image, not six boxed fields
        // and two full URL strings. Construct the few visible entries on demand.
        const names = new Array(assetCount);
        const locations = new Uint32Array(assetCount * 3);
        const byPath = new Map();
        value.packs.forEach((pack, index) => {
          let offset = 0;
          for (let i=pack[3];i<pack[4];i++) {
            const [name, length] = value.assets[i];
            names[i] = name; byPath.set(name,i);
            locations.set([length,index,offset], i*3);
            byteOffsets[i+1] = byteOffsets[i]+length;
            offset += length;
          }
          if (offset !== pack[2]) throw new Error('Map pack index mismatch');
        });
        const {assets, ...metadata} = value;
        return {...metadata,names,locations,byPath,assetCount,byteOffsets};
      }
      if (value.packSchema === 1) {
        value.packs.forEach((pack, index) => {
          let offset = 0;
          for (let i = pack[3]; i < pack[4]; i++) {
            value.assets[i].push(index, offset, i);
            offset += value.assets[i][2];
          }
          if (offset !== pack[2]) throw new Error('Map pack index mismatch');
        });
      }
      const byPath = new Map(value.assets.map(entry => [new URL(entry[0], ROOT).pathname, entry]));
      value.assets.forEach((entry, i) => {byteOffsets[i + 1] = byteOffsets[i] + entry[2];});
      return {...value, byPath, assetCount, byteOffsets};
    })().catch(error => {inventoryPromise = null; throw error;});
  }
  return inventoryPromise;
}

function assetEntry(data, index) {
  if (index == null || index < 0 || index >= data.assetCount) return;
  if (data.packSchema !== 2) return data.assets[index];
  const p=index*3;
  return [data.assetPrefix+data.names[index], null, data.locations[p],data.locations[p+1],data.locations[p+2],index];
}
function findAsset(data, pathname) {
  if(data.packSchema !== 2) return data.byPath.get(pathname);
  const prefix=ROOT.pathname+data.assetPrefix;
  if(!pathname.startsWith(prefix)) return;
  return assetEntry(data,data.byPath.get(pathname.slice(prefix.length)));
}

async function storedImage(entry, mustStore = false) {
  const data = await inventory();
  if (data.packSchema >= 1) return packedImage(data, entry);
  const key = keyFor(entry);
  const store = await caches.open(STORE);
  const local = await store.match(key);
  if (local) {
    if (mustStore) { await local.body?.cancel(); return; }
    return local;
  }
  if (!transfers.has(key)) {
    const pending = (async () => {
      const abort = new AbortController();
      const timeout = setTimeout(() => abort.abort(), 20000);
      let bytes;
      try {
        const response = await fetch(new URL(`${entry[0]}?map-sha256=${entry[1]}`, ROOT), {cache: 'no-store', signal: abort.signal});
        if (!response.ok) throw new Error(`Map image HTTP ${response.status}`);
        bytes = await response.arrayBuffer();
      } finally { clearTimeout(timeout); }
      if (bytes.byteLength !== entry[2]) throw new Error('Map image length mismatch');
      const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
        .map(byte => byte.toString(16).padStart(2, '0')).join('');
      if (digest !== entry[1]) throw new Error('Map image checksum mismatch');
      const saved = new Response(bytes, {headers: {
        'Content-Type': entry[0].endsWith('.json') ? 'application/json' : 'image/webp',
        'Content-Length': String(bytes.byteLength),
      }});
      let storageError;
      // Cache.put consumes the only response body. An unread clone/tee can keep
      // native byte buffers alive long after a background download finishes.
      try { await store.put(key, saved); } catch (error) { storageError = error; }
      return storageError ? {bytes, storageError} : {};
    })().finally(() => transfers.delete(key));
    transfers.set(key, pending);
  }
  const result = await transfers.get(key);
  if (mustStore && result.storageError) throw result.storageError;
  if (mustStore) return;
  if (result.storageError) {
    return new Response(result.bytes, {headers: {'Content-Type': entry[0].endsWith('.json') ? 'application/json' : 'image/webp'}});
  }
  const response = await store.match(key);
  if (!response) throw new Error('Stored map image unavailable');
  return response;
}

// Packs reduce tens of thousands of HTTP and CacheStorage operations to a few
// hundred. Each transfer is <= 1 MiB (apart from a single larger source asset).
async function storedPack(pack, storeName = PACK_STORE, downloadBase = ROOT) {
  const key = keyFor(pack);
  const store = await caches.open(storeName);
  const cached = await store.match(key);
  if (cached) {await cached.body?.cancel(); return;}
  if (!transfers.has(key)) {
    const pending = (async () => {
      const abort = new AbortController();
      const timeout = setTimeout(() => abort.abort(), 60000);
      const hash = new sha256.Hash();
      let length = 0;
      try {
        const response = await fetch(new URL(`${pack[0]}?map-sha256=${pack[1]}`, downloadBase), {cache: 'no-store', signal: abort.signal});
        if (!response.ok) throw new Error(`Map pack HTTP ${response.status}`);
        const checked = response.body.pipeThrough(new TransformStream({
          transform(chunk, controller) {
            length += chunk.byteLength;
            if (length > pack[2]) throw new Error('Map pack length mismatch');
            hash.update(chunk);
            controller.enqueue(chunk);
          },
          flush() {
            if (length !== pack[2]) throw new Error('Map pack length mismatch');
            const digest = [...hash.digest()].map(byte => byte.toString(16).padStart(2, '0')).join('');
            if (digest !== pack[1]) throw new Error('Map pack checksum mismatch');
          },
        }));
        // Consume the network stream once, validating it before Cache.put commits.
        // Never materialize a whole pack or copy it into a second Response body.
        await store.put(key, new Response(checked));
      } catch (error) {
        await store.delete(key);
        throw error;
      } finally {clearTimeout(timeout); hash.clean();}
    })().finally(() => transfers.delete(key));
    transfers.set(key, pending);
  }
  await transfers.get(key);
}

// One eighth of the shared retained-image budget is compressed bytes;
// Flutter owns the remaining shared decoded-background/boundary budget.
// Foreground-only compressed LRU. Downloading never fills this memory cache.
// Keep the selected byte limit resident and at most two one-pack disk reads in flight; these
// bytes are not decoded pixels or GPU surfaces.
const MEMORY_CHOICES = [32, 64, 128, 256];
const memorySettingsKey = new URL('__map_memory_settings__', ROOT).href;
let mapMemoryMegabytes = 32;
let packMemoryLimit = mapMemoryMegabytes * 1024 * 1024 / 8;
let memorySettingsPromise;
let memorySettingsQueue = Promise.resolve();
function loadMemorySettings() {
  if (!memorySettingsPromise) memorySettingsPromise = (async () => {
    const response = await (await caches.open(META)).match(memorySettingsKey);
    const value = response ? (await response.json()).megabytes : 32;
    mapMemoryMegabytes = MEMORY_CHOICES.includes(value) ? value : 32;
    packMemoryLimit = mapMemoryMegabytes * 1024 * 1024 / 8;
  })().catch(() => {memorySettingsPromise = null;});
  return memorySettingsPromise;
}
function trimPackMemory() {
  while (packMemoryBytes > packMemoryLimit) {
    const oldest = packMemory.keys().next().value;
    packMemoryBytes -= packMemory.get(oldest).length;
    packMemory.delete(oldest);
  }
}
function setMemorySettings(megabytes) {
  const operation = memorySettingsQueue.then(async () => {
    if (!MEMORY_CHOICES.includes(megabytes)) throw new Error('Invalid map memory size');
    await loadMemorySettings();
    await (await caches.open(META)).put(memorySettingsKey, new Response(JSON.stringify({megabytes})));
    mapMemoryMegabytes = megabytes;
    packMemoryLimit = megabytes * 1024 * 1024 / 8;
    trimPackMemory();
    return {megabytes};
  });
  memorySettingsQueue = operation.catch(() => {});
  return operation;
}
const packMemory = new Map();
const packReads = new Map();
const packReadWaiters = [];
let packMemoryBytes = 0;
let packReading = 0;
async function readStoredBytes(pack, storeName = PACK_STORE) {
  await loadMemorySettings();
  const key = keyFor(pack);
  const cached = packMemory.get(key);
  if (cached) {
    packMemory.delete(key);
    packMemory.set(key, cached);
    return cached;
  }
  if (packReads.has(key)) return packReads.get(key);
  const pending = (async () => {
    if (packReading < 2) packReading++;
    else await new Promise(resolve => packReadWaiters.push(resolve));
    try {
      const response = await (await caches.open(storeName)).match(key);
      if (!response) return;
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.length !== pack[2]) throw new Error('Stored map pack truncated');
      if (bytes.length <= packMemoryLimit) {
        while (packMemoryBytes + bytes.length > packMemoryLimit) {
          const oldest = packMemory.keys().next().value;
          packMemoryBytes -= packMemory.get(oldest).length;
          packMemory.delete(oldest);
        }
        packMemory.set(key, bytes);
        packMemoryBytes += bytes.length;
      }
      return bytes;
    } finally {
      if (packReadWaiters.length) packReadWaiters.shift()();
      else packReading--;
    }
  })().finally(() => packReads.delete(key));
  packReads.set(key, pending);
  return pending;
}

async function packedImage(data, entry) {
  const legacyKey = keyFor(entry);
  const residentLegacy = data.packSchema === 1 && packMemory.get(legacyKey);
  if (residentLegacy) {
    packMemory.delete(legacyKey);
    packMemory.set(legacyKey, residentLegacy);
    return imageResponse(residentLegacy, entry, 0);
  }
  const pack = data.packs[entry[3]];
  let bytes = await readStoredBytes(pack);
  if (!bytes) {
    const legacy = data.packSchema === 1 && await readStoredBytes(entry, STORE);
    if (legacy) return imageResponse(legacy, entry, 0);
    await storedPack(pack, PACK_STORE, data.packBaseUrl || ROOT);
    bytes = await readStoredBytes(pack);
  }
  if (!bytes) throw new Error('Stored map pack unavailable');
  // Response copies only the requested image, not its entire compressed pack.
  return imageResponse(bytes, entry, entry[4]);
}

function imageResponse(bytes, entry, offset) {
  return new Response(bytes.subarray(offset, offset + entry[2]), {headers: {
    'Content-Type': entry[0].endsWith('.json') ? 'application/json' : 'image/webp',
    'Content-Length': String(entry[2]),
  }});
}

async function downloadPackWindow(packs, first, storeName, downloadBase = ROOT) {
  const deadline = Date.now() + DOWNLOAD_WINDOW_MS;
  const end = Math.min(first + DOWNLOAD_WINDOW_PACKS, packs.length);
  const completed = new Set();
  let cursor = first, failure;
  await Promise.all(Array.from({length: DOWNLOAD_CONCURRENCY}, async () => {
    while (!failure && cursor < end && Date.now() < deadline) {
      const index = cursor++;
      try {
        await storedPack(packs[index], storeName, downloadBase);
        completed.add(index);
      } catch (error) {failure = error;}
    }
  }));
  // Out-of-order successes remain on disk. Persist only the uninterrupted
  // prefix so a failed/interrupted request cannot be mistaken for a saved pack.
  let next = first;
  while (completed.has(next)) next++;
  return {next, failure};
}

async function warmPacks(data, meta, progress) {
  const start = progress.next;
  if (start === data.assetCount && progress.cleaned) return progressReport(data, start, true);
  const first = assetEntry(data,start)?.[3] ?? data.packs.length;
  const result = await downloadPackWindow(data.packs, first, PACK_STORE, data.packBaseUrl || ROOT);
  const end = result.next > first ? data.packs[result.next - 1][4] : start;
  const legacy = progress.legacy ?? start;
  const complete = end === data.assetCount;
  await meta.put(progressKey, new Response(JSON.stringify({next: end, legacy})));
  if (result.failure) throw result.failure;
  if (complete) {
    await removeOldVersions(data, meta);
    await meta.put(progressKey, new Response(JSON.stringify({next: end, legacy, cleaned: true})));
  }
  return progressReport(data, end, complete);
}

async function removeOldVersions(data, meta) {
  const store = await caches.open(STORE);
  // All new prepared packs are verified before this point. The legacy image
  // store is separate from game saves and can be retired in one operation,
  // instead of tens of thousands of serialized Cache.delete calls on iOS.
  if (data.packSchema === 2) await caches.delete(STORE);
  // Do not enumerate 44,000 CacheStorage Request objects. Only obsolete
  // manifests describe image versions that actually need deleting.
  for (const request of await meta.keys()) {
    if (request.url !== memorySettingsKey && request.url !== progressKey &&
        request.url !== new URL(`map-image-manifest.json?packs=1&v=${REVISION}`, ROOT).href) {
      if (new URL(request.url).pathname.endsWith('/map-image-manifest.json')) {
        const old = await (await meta.match(request)).json();
        const currentPacks = new Set((data.packs || []).map(pack => keyFor(pack)));
        const packedStore = await caches.open(PACK_STORE);
        for (const pack of old.packs || []) {
          if (!currentPacks.has(keyFor(pack))) await packedStore.delete(keyFor(pack));
        }
        for (const entry of data.packSchema === 2 || old.packSchema === 2 ? [] : old.assets) {
          const current = findAsset(data,new URL(entry[0], ROOT).pathname);
          if (!current || current[1] !== entry[1]) await store.delete(keyFor(entry));
        }
      }
      await meta.delete(request);
    }
  }
}

function progressReport(data, next, done) {
  return {done, saved: next, total: data.assetCount, savedBytes: data.byteOffsets[next], bytes: data.bytes};
}

async function imageStorageStatus() {
  const data = await inventory();
  const meta = await caches.open(META);
  const saved = await meta.match(progressKey);
  const progress = saved ? await saved.json() : {next: 0};
  return progressReport(data, progress.next, progress.next === data.assetCount && !!progress.cleaned);
}

async function imageWarmBatch() {
  const data = await inventory();
  const meta = await caches.open(META);
  const saved = await meta.match(progressKey);
  const progress = saved ? await saved.json() : {next: 0};
  if (data.packSchema >= 1) return warmPacks(data, meta, progress);
  const start = progress.next;
  if (start === data.assetCount && progress.cleaned) {
    return progressReport(data, start, true);
  }
  const end = Math.min(start + BATCH, data.assetCount);
  let cursor = start;
  let failure;
  await Promise.all(Array.from({length: CONCURRENCY}, async () => {
    while (cursor < end && !failure) {
      const entry = assetEntry(data,cursor++);
      try { await storedImage(entry, true); } catch (error) { failure = error; }
    }
  }));
  // A failed batch is resumed from its beginning; already saved images are reused.
  if (failure) throw failure;
  if (start !== end || !saved) {
    await meta.put(progressKey, new Response(JSON.stringify({next: end})));
  }
  if (end === data.assetCount) {
    await removeOldVersions(data, meta);
    await meta.put(progressKey, new Response(JSON.stringify({next: end, cleaned: true})));
  }
  return progressReport(data, end, end === data.assetCount);
}


// All non-image runtime files are verified on disk too. Large files use bounded
// gzip chunks; neither initial download nor disk reads buffer a complete county.
const RUNTIME_REVISION = '__RUNTIME_DATA_REVISION__';
const RUNTIME_STORE = 'kunitori-runtime-data-v1';
const RUNTIME_META = 'kunitori-runtime-meta-v1';
let runtimeInventoryPromise;
async function runtimeInventory() {
  // Source-only legacy fixtures have no prepared runtime manifest.
  if (RUNTIME_REVISION.startsWith('__')) return {chunks:[],files:[],bytes:0,byPath:new Map()};
  if (!runtimeInventoryPromise) runtimeInventoryPromise = (async () => {
    const meta = await caches.open(RUNTIME_META);
    const key = new URL(`runtime-data-manifest.json?v=${RUNTIME_REVISION}`, ROOT).href;
    let response = await meta.match(key), data;
    if (response) data = await response.json();
    else {
      response = await fetch(key,{cache:'no-cache'});
      if (!response.ok) throw Error(`Runtime inventory HTTP ${response.status}`);
      data = await response.json();
      if (data.revision !== RUNTIME_REVISION) throw Error('Runtime inventory version mismatch');
      await meta.put(key,new Response(JSON.stringify(data)));
    }
    data.byPath = new Map(data.files.map(f=>[new URL(f.path,ROOT).pathname,f]));
    return data;
  })().catch(error=>{runtimeInventoryPromise=null;throw error;});
  return runtimeInventoryPromise;
}
async function runtimeProgress(data, warm=false) {
  const meta = await caches.open(RUNTIME_META);
  const key = new URL(`__runtime_progress__/${RUNTIME_REVISION}`,ROOT).href;
  const saved = await meta.match(key);
  let next = saved ? (await saved.json()).next : 0;
  if (warm && next<data.chunks.length) {
    const result = await downloadPackWindow(data.chunks, next, RUNTIME_STORE);
    next=result.next;
    await meta.put(key,new Response(JSON.stringify({next})));
    if (result.failure) throw result.failure;
  }
  return {done:next===data.chunks.length,saved:next,total:data.chunks.length,
    savedBytes:data.chunks.slice(0,next).reduce((n,c)=>n+c[2],0),bytes:data.bytes};
}
function combinedProgress(images,runtime) {
  return {done:images.done&&runtime.done,saved:images.saved+runtime.saved,total:images.total+runtime.total,
    savedBytes:images.savedBytes+runtime.savedBytes,bytes:images.bytes+runtime.bytes};
}
async function storageStatus() {
  return combinedProgress(await imageStorageStatus(),await runtimeProgress(await runtimeInventory()));
}
async function warmBatch() {
  const before=await imageStorageStatus();
  const images=before.done ? before : await imageWarmBatch();
  // One transfer phase per message bounds the time until a progress response,
  // including on a slow connection. The next message starts runtime chunks.
  return combinedProgress(images,await runtimeProgress(await runtimeInventory(),before.done));
}
async function runtimeResponse(data,file) {
  let index=0, reader;
  const stream = new ReadableStream({
    async pull(controller) {
      try {
        for (;;) {
          if (!reader) {
            if (index===file.chunks.length) {controller.close();return;}
            const chunk=data.chunks[file.chunks[index++]];
            let response=await (await caches.open(RUNTIME_STORE)).match(keyFor(chunk));
            if (!response) {await storedPack(chunk,RUNTIME_STORE);response=await (await caches.open(RUNTIME_STORE)).match(keyFor(chunk));}
            reader=response.body.getReader();
          }
          const result=await reader.read();
          if (result.done) {reader.releaseLock();reader=null;continue;}
          controller.enqueue(result.value);return;
        }
      } catch(error) {controller.error(error);}
    },
    cancel(reason) {return reader?.cancel(reason);},
  });
  return new Response(stream.pipeThrough(new DecompressionStream('gzip')),{headers:{
    'Content-Type':file.mime,'Content-Length':String(file.bytes),
  }});
}
self.addEventListener('fetch',event=>{
  const url=new URL(event.request.url);
  if(event.request.method!=='GET'||url.origin!==ROOT.origin) return;
  const relative=url.pathname.slice(ROOT.pathname.length);
  const shell=relative===''||['index.html','flutter_bootstrap.js','map-cache.js','diagnostics.js'].includes(relative);
  const asset=relative==='main.dart.js'||relative.startsWith('assets/')||relative.startsWith('canvaskit/');
  if(!shell&&!asset || relative.startsWith('assets/assets/data/map_images/') && relative.endsWith('.webp')) return;
  event.respondWith((async()=>{
    if(shell) {try {const response=await fetch(event.request);if(response.ok)return response;}catch(_) {}}
    const data=await runtimeInventory();
    const file=findAsset(data,url.pathname)|| (relative==='' ? data.byPath.get(new URL('index.html',ROOT).pathname):null);
    return file ? runtimeResponse(data,file) : fetch(event.request);
  })());
});

self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('message', event => {
  if (!event.ports[0]) return;
  if (['map-memory-get', 'map-memory-set', 'map-memory-release'].includes(event.data?.type)) {
    const operation = event.data.type === 'map-memory-set'
      ? setMemorySettings(event.data.megabytes)
      : memorySettingsQueue.then(async () => {
        await loadMemorySettings();
        if (event.data.type === 'map-memory-release') {
          await Promise.allSettled([...packReads.values()]);
          packMemory.clear();
          packMemoryBytes = 0;
        }
        return {megabytes: mapMemoryMegabytes, bytes: packMemoryBytes};
      });
    event.waitUntil(operation.then(
      result => event.ports[0].postMessage(result),
      error => event.ports[0].postMessage({error: String(error)}),
    ));
    return;
  }
  if (event.data?.type === 'map-images-status') {
    event.waitUntil(storageStatus().then(
      result => event.ports[0].postMessage(result),
      error => event.ports[0].postMessage({error: String(error)}),
    ));
    return;
  }
  if (event.data?.type !== 'warm-map-images') return;
  // Multiple tabs share one bounded batch and the same in-flight transfers.
  if (!warming) warming = warmBatch().finally(() => {warming = null;});
  event.waitUntil(warming.then(
    result => event.ports[0].postMessage(result),
    error => event.ports[0].postMessage({error: String(error)}),
  ));
});
let memoryNotice;
function reportMemoryAfterRead() {
  if (!memoryNotice) memoryNotice = new Promise(resolve => {
    setTimeout(async () => {
      try {
        const clients = await self.clients.matchAll({type: 'window'});
        for (const client of clients) client.postMessage({
          type: 'map-memory-state', megabytes: mapMemoryMegabytes,
          bytes: packMemoryBytes,
        });
      } catch (_) {} finally {memoryNotice = null; resolve();}
    }, 1000);
  });
  return memoryNotice;
}

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== ROOT.origin || !url.pathname.endsWith('.webp') ||
      !['map_images'].some(folder =>
        url.pathname.startsWith(`${ROOT.pathname}assets/assets/data/${folder}/`))) return;
  const response = (async () => {
    let data;
    try { data = await inventory(); } catch (_) { return fetch(event.request); }
    const entry = findAsset(data,url.pathname);
    return entry ? storedImage(entry) : fetch(event.request);
  })();
  event.respondWith(response);
  event.waitUntil(response.then(reportMemoryAfterRead, () => {}));
});

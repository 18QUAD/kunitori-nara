/* Compressed map bytes live on disk, independently of Flutter/GPU image caches. */
'use strict';
const REVISION = '__MAP_IMAGE_REVISION__';
const ROOT = new URL('./', self.location.href);
const STORE = 'kunitori-map-images-v1';
const PACK_STORE = 'kunitori-map-packs-v1';
const META = 'kunitori-map-images-meta-v1';
const BATCH = 48;
const CONCURRENCY = 2;
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
      const byteOffsets = new Float64Array(value.assets.length + 1);
      value.assets.forEach((entry, i) => {byteOffsets[i + 1] = byteOffsets[i] + entry[2];});
      return {...value, byPath, byteOffsets};
    })().catch(error => {inventoryPromise = null; throw error;});
  }
  return inventoryPromise;
}

async function storedImage(entry, mustStore = false) {
  const data = await inventory();
  if (data.packSchema === 1) return packedImage(data, entry);
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
async function storedPack(pack) {
  const key = keyFor(pack);
  const store = await caches.open(PACK_STORE);
  const cached = await store.match(key);
  if (cached) {await cached.body?.cancel(); return;}
  if (!transfers.has(key)) {
    const pending = (async () => {
      const abort = new AbortController();
      const timeout = setTimeout(() => abort.abort(), 60000);
      const hash = new sha256.Hash();
      let length = 0;
      try {
        const response = await fetch(key, {cache: 'no-store', signal: abort.signal});
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

// Foreground-only compressed LRU. Downloading never fills this memory cache.
// Keep <= 8 MiB resident and at most two one-pack disk reads in flight; these
// bytes are not decoded pixels or GPU surfaces.
const PACK_MEMORY_BYTES = 8 * 1024 * 1024;
const packMemory = new Map();
const packReads = new Map();
const packReadWaiters = [];
let packMemoryBytes = 0;
let packReading = 0;
async function readStoredBytes(pack, storeName = PACK_STORE) {
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
      if (bytes.length <= PACK_MEMORY_BYTES) {
        while (packMemoryBytes + bytes.length > PACK_MEMORY_BYTES) {
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
  const residentLegacy = packMemory.get(legacyKey);
  if (residentLegacy) {
    packMemory.delete(legacyKey);
    packMemory.set(legacyKey, residentLegacy);
    return imageResponse(residentLegacy, entry, 0);
  }
  const pack = data.packs[entry[3]];
  let bytes = await readStoredBytes(pack);
  if (!bytes) {
    const legacy = await readStoredBytes(entry, STORE);
    if (legacy) return imageResponse(legacy, entry, 0);
    await storedPack(pack);
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

async function warmPacks(data, meta, progress) {
  const start = progress.next;
  if (start === data.assets.length && progress.cleaned) return progressReport(data, start, true);
  const first = data.assets[start]?.[3] ?? data.packs.length;
  const batch = data.packs.slice(first, first + CONCURRENCY);
  // Wait for both operations even on failure: a retry must not overlap unfinished
  // storage writes from the preceding batch.
  const results = await Promise.allSettled(batch.map(pack => storedPack(pack)));
  const failure = results.find(result => result.status === 'rejected');
  if (failure) throw failure.reason;
  const end = batch.length ? batch[batch.length - 1][4] : start;
  const legacy = progress.legacy ?? start;
  const complete = end === data.assets.length;
  await meta.put(progressKey, new Response(JSON.stringify({next: end, legacy})));
  if (complete) {
    await removeOldVersions(data, meta);
    await meta.put(progressKey, new Response(JSON.stringify({next: end, legacy, cleaned: true})));
  }
  return progressReport(data, end, complete);
}

async function removeOldVersions(data, meta) {
  const store = await caches.open(STORE);
  // Do not enumerate 44,000 CacheStorage Request objects. Only obsolete
  // manifests describe image versions that actually need deleting.
  for (const request of await meta.keys()) {
    if (request.url !== progressKey &&
        request.url !== new URL(`map-image-manifest.json?packs=1&v=${REVISION}`, ROOT).href) {
      if (new URL(request.url).pathname.endsWith('/map-image-manifest.json')) {
        const old = await (await meta.match(request)).json();
        const currentPacks = new Set((data.packs || []).map(pack => keyFor(pack)));
        const packedStore = await caches.open(PACK_STORE);
        for (const pack of old.packs || []) {
          if (!currentPacks.has(keyFor(pack))) await packedStore.delete(keyFor(pack));
        }
        for (const entry of old.assets) {
          const current = data.byPath.get(new URL(entry[0], ROOT).pathname);
          if (!current || current[1] !== entry[1]) await store.delete(keyFor(entry));
        }
      }
      await meta.delete(request);
    }
  }
}

function progressReport(data, next, done) {
  return {done, saved: next, total: data.assets.length, savedBytes: data.byteOffsets[next], bytes: data.bytes};
}

async function storageStatus() {
  const data = await inventory();
  const meta = await caches.open(META);
  const saved = await meta.match(progressKey);
  const progress = saved ? await saved.json() : {next: 0};
  return progressReport(data, progress.next, progress.next === data.assets.length && !!progress.cleaned);
}

async function warmBatch() {
  const data = await inventory();
  const meta = await caches.open(META);
  const saved = await meta.match(progressKey);
  const progress = saved ? await saved.json() : {next: 0};
  if (data.packSchema === 1) return warmPacks(data, meta, progress);
  const start = progress.next;
  if (start === data.assets.length && progress.cleaned) {
    return progressReport(data, start, true);
  }
  const end = Math.min(start + BATCH, data.assets.length);
  let cursor = start;
  let failure;
  await Promise.all(Array.from({length: CONCURRENCY}, async () => {
    while (cursor < end && !failure) {
      const entry = data.assets[cursor++];
      try { await storedImage(entry, true); } catch (error) { failure = error; }
    }
  }));
  // A failed batch is resumed from its beginning; already saved images are reused.
  if (failure) throw failure;
  if (start !== end || !saved) {
    await meta.put(progressKey, new Response(JSON.stringify({next: end})));
  }
  if (end === data.assets.length) {
    await removeOldVersions(data, meta);
    await meta.put(progressKey, new Response(JSON.stringify({next: end, cleaned: true})));
  }
  return progressReport(data, end, end === data.assets.length);
}

self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('message', event => {
  if (!event.ports[0]) return;
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
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== ROOT.origin ||
      !['map_tiles_uniform', 'border_tiles'].some(folder =>
        url.pathname.startsWith(`${ROOT.pathname}assets/assets/data/${folder}/`))) return;
  event.respondWith((async () => {
    let data;
    try { data = await inventory(); } catch (_) { return fetch(event.request); }
    const entry = data.byPath.get(url.pathname);
    return entry ? storedImage(entry) : fetch(event.request);
  })());
});

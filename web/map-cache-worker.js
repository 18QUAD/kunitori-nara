/* Compressed map bytes live on disk, independently of Flutter/GPU image caches. */
'use strict';
const REVISION = '__MAP_IMAGE_REVISION__';
const ROOT = new URL('./', self.location.href);
const STORE = 'kunitori-map-images-v1';
const META = 'kunitori-map-images-meta-v1';
const BATCH = 48;
const CONCURRENCY = 4;
let inventoryPromise;
let warming;
const transfers = new Map();
const keyFor = entry => new URL(`${entry[0]}?map-sha256=${entry[1]}`, ROOT).href;
const progressKey = new URL(`__map_progress__/${REVISION}`, ROOT).href;

async function inventory() {
  if (!inventoryPromise) {
    inventoryPromise = (async () => {
      const meta = await caches.open(META);
      const url = new URL(`map-image-manifest.json?v=${REVISION}`, ROOT).href;
      let response = await meta.match(url);
      if (!response) {
        response = await fetch(url, {cache: 'no-cache'});
        if (!response.ok) throw new Error(`Map inventory HTTP ${response.status}`);
        // Validate before persisting; a deployment can briefly serve mixed files.
        const value = await response.clone().json();
        if (value.schema !== 1 || value.revision !== REVISION) throw new Error('Map inventory version mismatch');
        await meta.put(url, response.clone());
      }
      const value = await response.json();
      const byPath = new Map(value.assets.map(entry => [new URL(entry[0], ROOT).pathname, entry]));
      return {...value, byPath};
    })().catch(error => {inventoryPromise = null; throw error;});
  }
  return inventoryPromise;
}

async function storedImage(entry, mustStore = false) {
  const key = keyFor(entry);
  const store = await caches.open(STORE);
  const local = await store.match(key);
  if (local) return local;
  if (!transfers.has(key)) {
    const pending = (async () => {
      const abort = new AbortController();
      const timeout = setTimeout(() => abort.abort(), 20000);
      let bytes;
      try {
        const response = await fetch(new URL(`${entry[0]}?map-sha256=${entry[1]}`, ROOT), {cache: 'no-cache', signal: abort.signal});
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
      try { await store.put(key, saved.clone()); } catch (error) { storageError = error; }
      return {response: saved, storageError};
    })().finally(() => transfers.delete(key));
    transfers.set(key, pending);
  }
  const result = await transfers.get(key);
  if (mustStore && result.storageError) throw result.storageError;
  return result.response.clone();
}

async function removeOldVersions(data, meta) {
  const store = await caches.open(STORE);
  // Do not enumerate 44,000 CacheStorage Request objects. Only obsolete
  // manifests describe image versions that actually need deleting.
  for (const request of await meta.keys()) {
    if (request.url !== progressKey &&
        request.url !== new URL(`map-image-manifest.json?v=${REVISION}`, ROOT).href) {
      if (new URL(request.url).pathname.endsWith('/map-image-manifest.json')) {
        const old = await (await meta.match(request)).json();
        for (const entry of old.assets) {
          const current = data.byPath.get(new URL(entry[0], ROOT).pathname);
          if (!current || current[1] !== entry[1]) await store.delete(keyFor(entry));
        }
      }
      await meta.delete(request);
    }
  }
}

async function warmBatch() {
  const data = await inventory();
  const meta = await caches.open(META);
  const saved = await meta.match(progressKey);
  const progress = saved ? await saved.json() : {next: 0};
  const start = progress.next;
  if (start === data.assets.length && progress.cleaned) {
    return {done: true, saved: start, total: start, bytes: data.bytes};
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
  return {done: end === data.assets.length, saved: end, total: data.assets.length, bytes: data.bytes};
}

self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('message', event => {
  if (event.data?.type !== 'warm-map-images' || !event.ports[0]) return;
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

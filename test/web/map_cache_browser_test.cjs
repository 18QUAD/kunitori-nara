// Real CacheStorage + service worker: interruption, offline hits and delta updates.
const {chromium} = require('playwright');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const workerSource = fs.readFileSync('web/map-cache-worker.js', 'utf8');
const clientSource = fs.readFileSync('web/map-cache.js', 'utf8');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'kunitori-map-cache-'));
const root = '/kunitori-nara/';
const imagePaths = Array.from({length: 100}, (_, i) => `assets/assets/data/map_tiles_uniform/dry_${i}_detail.webp`);
const contents = new Map(imagePaths.map((name, i) => [name, Buffer.from(`image-bytes-${i}`)]));
let version = 1;
let requests = new Map();
let failOnce = imagePaths[60];
let wrongOnce = imagePaths[61];
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function manifest() {
  const assets = [...contents].map(([name, bytes]) => [name, sha(bytes), bytes.length]);
  return {schema: 1, revision: String(version), bytes: assets.reduce((n, x) => n + x[2], 0), assets};
}
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const name = url.pathname.slice(root.length);
  res.setHeader('Cache-Control', 'no-store');
  if (name === '') {
    res.setHeader('Content-Type', 'text/html');
    res.end(`<script src="map-cache.js?v=${version}"></script>`);
  } else if (name === 'map-cache.js') {
    res.setHeader('Content-Type', 'application/javascript'); res.end(clientSource);
  } else if (name === 'map-cache-worker.js') {
    res.setHeader('Content-Type', 'application/javascript');
    res.end(workerSource.replace('__MAP_IMAGE_REVISION__', String(version)));
  } else if (name === 'map-image-manifest.json') {
    res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(manifest()));
  } else if (contents.has(name)) {
    requests.set(name, (requests.get(name) || 0) + 1);
    if (name === failOnce) {failOnce = null; res.writeHead(503); res.end('retry');}
    else if (name === wrongOnce) {wrongOnce = null; res.end('invalid checksum');}
    else setTimeout(() => res.end(contents.get(name)), 5);
  } else {res.writeHead(404); res.end();}
});
let context;
async function open(base) {
  context = await chromium.launchPersistentContext(profile, {
    executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    headless: true, args: ['--no-sandbox'],
  });
  const page = context.pages()[0];
  await page.goto(base);
  await page.evaluate(() => window.kunitoriMapStorage);
  return page;
}
async function progress(page) {
  return page.evaluate(async version => {
    const cache = await caches.open('kunitori-map-images-meta-v1');
    const response = await cache.match(new URL(`__map_progress__/${version}`, location.href));
    return response ? response.json() : {next: 0};
  }, version);
}
async function waitUntil(check, message) {
  const deadline = Date.now() + 30000;
  while (!(await check())) {
    assert(Date.now() < deadline, message);
    await new Promise(resolve => setTimeout(resolve, 25));
  }
}
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}${root}`;
  let page = await open(base);
  await page.evaluate(() => localStorage.setItem('flutter.kunitori.nara.v1', 'preserve-game-save'));
  await waitUntil(async () => (await progress(page)).next >= 48, 'First batch did not finish');
  await context.close();
  const downloaded = new Map(requests);
  page = await open(base);
  await waitUntil(async () => (await progress(page)).cleaned, 'Interrupted download did not resume');
  for (let i = 0; i < 48; i++) assert.equal(requests.get(imagePaths[i]), downloaded.get(imagePaths[i]), 'Saved bytes downloaded again');
  assert.equal(requests.get(imagePaths[60]), 2, 'Temporary HTTP failure must retry');
  assert.equal(requests.get(imagePaths[61]), 2, 'Invalid bytes must retry rather than be cached');
  assert.equal(await page.evaluate(() => localStorage.getItem('flutter.kunitori.nara.v1')), 'preserve-game-save');
  const completeCounts = new Map(requests);
  await context.close();
  page = await open(base);
  await context.setOffline(true);
  const offline = await page.evaluate(async names => {
    return Promise.all(names.map(async name => (await fetch(name)).text()));
  }, imagePaths);
  assert.deepEqual(offline, [...contents.values()].map(bytes => bytes.toString()));
  assert.deepEqual(requests, completeCounts, 'Completed store must not request image bytes again');
  await context.setOffline(false);
  // A newer dataset downloads one changed image, reuses 99 and retires the old copy.
  contents.set(imagePaths[99], Buffer.from('updated-image-99'));
  version++;
  await page.reload();
  await page.evaluate(() => window.kunitoriMapStorage);
  await waitUntil(async () => (await progress(page)).cleaned, 'Delta update did not complete');
  for (let i = 0; i < 99; i++) assert.equal(requests.get(imagePaths[i]), completeCounts.get(imagePaths[i]));
  assert.equal(requests.get(imagePaths[99]), completeCounts.get(imagePaths[99]) + 1);
  assert.equal(await page.evaluate(async () => (await (await caches.open('kunitori-map-images-v1')).keys()).length), 100);
  assert.equal(await page.evaluate(() => localStorage.getItem('flutter.kunitori.nara.v1')), 'preserve-game-save');
  console.log('PASS: persistent disk images, restart/resume, HTTP/checksum retries, offline reads, delta updates, stale-image cleanup and save preservation.');
})().finally(async () => {
  if (context) await context.close();
  server.close();
  fs.rmSync(profile, {recursive: true, force: true});
}).catch(error => {console.error(error); process.exitCode = 1;});

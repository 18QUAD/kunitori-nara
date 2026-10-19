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
const styles = fs.readFileSync('web/index.html', 'utf8').match(/<style>([\s\S]*?)<\/style>/)[1];
const bootstrap = fs.readFileSync('web/flutter_bootstrap.js', 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '')
  .replaceAll('{{flutter_service_worker_version}}', 'fixture');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'kunitori-map-cache-'));
const root = '/kunitori-nara/';
const imagePaths = Array.from({length: 100}, (_, i) => `assets/assets/data/map_tiles_uniform/dry_${i}_detail.webp`);
const contents = new Map(imagePaths.map((name, i) => [name, Buffer.from(`image-bytes-${i}`)]));
let version = 1;
let requests = new Map();
let failOnce = imagePaths[60];
let wrongOnce = imagePaths[61];
let workerFailure = true;
let workerRequests = 0;
let activeTransfers = 0;
let peakTransfers = 0;
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
    res.end(`<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${styles}</style><div id="app-host"></div><div id="safe-area-probe"></div><script>window.loaderStarts=0;window._flutter={buildConfig:{builds:[{mainJsPath:'fixture.js'}]},loader:{load(){window.loaderStarts++;}}};</script><script src="map-cache.js?v=${version}"></script><script src="bootstrap-test.js"></script>`);
  } else if (name === 'bootstrap-test.js') {
    res.setHeader('Content-Type', 'application/javascript'); res.end(bootstrap);
  } else if (name === 'map-cache.js') {
    res.setHeader('Content-Type', 'application/javascript'); res.end(clientSource);
  } else if (name === 'map-cache-worker.js') {
    workerRequests++;
    if (workerFailure) {workerFailure = false; res.writeHead(503); res.end('retry installation'); return;}
    res.setHeader('Content-Type', 'application/javascript');
    // Enumerating every stored image would create tens of thousands of Request
    // objects on the phone. Fail if the worker attempts that operation.
    const guard = `Response.prototype.clone = () => {throw new Error('Response cloning retains unread native buffers');};
      const originalOpen = caches.open.bind(caches);
      caches.open = async name => {
        const cache = await originalOpen(name);
        if (name === 'kunitori-map-images-v1') cache.keys = () => {throw new Error('Image-store enumeration exceeds memory budget');};
        return cache;
      };`;
    res.end(guard + workerSource.replace('__MAP_IMAGE_REVISION__', String(version)));
  } else if (name === 'map-image-manifest.json') {
    res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(manifest()));
  } else if (contents.has(name)) {
    activeTransfers++;
    peakTransfers = Math.max(peakTransfers, activeTransfers);
    res.on('finish', () => {activeTransfers--;});
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
    headless: true, args: ['--no-sandbox'], viewport: {width: 375, height: 667},
  });
  const page = context.pages()[0];
  page.on('pageerror', error => console.error('Page error:', error.message));
  page.on('console', message => {if (message.type() === 'error') console.error(message.text());});
  await page.addInitScript(() => {
    window.kunitoriDiagnostics = {record(event, json) {
      if (event === 'map_storage_retry') console.error(json);
    }};
  });
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
  // A visibility event between setup failure and its retry used to cancel recovery.
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
  await page.getByText('全国の地図データをダウンロード中', {exact: true}).waitFor();
  assert.equal(await page.evaluate(() => window.loaderStarts), 0, 'Game must not load while initial download is running');
  const bar = page.getByRole('progressbar', {name: '地図データのダウンロード', exact: true});
  assert.equal(await bar.evaluate(element => element.value), 0);
  await page.evaluate(() => localStorage.setItem('flutter.kunitori.nara.v1', 'preserve-game-save'));
  await waitUntil(async () => (await progress(page)).next >= 48, 'First batch did not finish');
  await waitUntil(async () => await bar.evaluate(element => element.value) > 0, 'Visible progress did not advance');
  const firstBytes = manifest().assets.slice(0, 48).reduce((sum, entry) => sum + entry[2], 0);
  const firstPercent = firstBytes / manifest().bytes * 100;
  assert.equal(await bar.evaluate(element => element.value), firstPercent);
  const layout = await page.evaluate(() => ({
    panel: document.getElementById('map-download-status').getBoundingClientRect().toJSON(),
    game: document.getElementById('app-host').getBoundingClientRect().toJSON(),
  }));
  assert.equal(layout.game.height, 0, 'Game stays hidden until initial storage completes');
  assert(layout.panel.height > 0);
  await context.setOffline(true);
  await page.getByText('接続を待っています。続きから再開します', {exact: true}).waitFor();
  assert.equal(await page.evaluate(() => window.loaderStarts), 0);
  assert.equal(await bar.evaluate(element => element.value), firstPercent, 'Offline state must retain progress');
  await context.close();
  const downloaded = new Map(requests);
  page = await open(base);
  await waitUntil(async () => await page.locator('#map-download-status progress').evaluate(element => element.value).catch(() => 0) >= firstPercent, 'Resumed UI lost saved bytes');
  await waitUntil(async () => (await progress(page)).cleaned, 'Interrupted download did not resume');
  assert(workerRequests >= 2, 'Failed worker installation must recover automatically');
  assert(peakTransfers <= 2, 'Disk downloads must use at most two simultaneous transfers');
  await page.locator('#map-download-status').waitFor({state: 'detached'});
  await page.waitForFunction(() => window.loaderStarts === 1);
  assert.equal(await page.evaluate(() => getComputedStyle(document.getElementById('app-host')).height), '667px');
  for (let i = 0; i < 48; i++) assert.equal(requests.get(imagePaths[i]), downloaded.get(imagePaths[i]), 'Saved bytes downloaded again');
  assert.equal(requests.get(imagePaths[60]), 2, 'Temporary HTTP failure must retry');
  assert.equal(requests.get(imagePaths[61]), 2, 'Invalid bytes must retry rather than be cached');
  assert.equal(await page.evaluate(() => localStorage.getItem('flutter.kunitori.nara.v1')), 'preserve-game-save');
  const completeCounts = new Map(requests);
  await context.close();
  page = await open(base);
  const insertions = await page.evaluate(() => {
    window.progressPanels = 0;
    new MutationObserver(records => {
      for (const record of records) for (const node of record.addedNodes) {
        if (node.id === 'map-download-status') window.progressPanels++;
      }
    }).observe(document.body, {childList: true});
    return document.querySelectorAll('#map-download-status').length;
  });
  await context.setOffline(true);
  const offline = await page.evaluate(async names => {
    return Promise.all(names.map(async name => (await fetch(name)).text()));
  }, imagePaths);
  assert.deepEqual(offline, [...contents.values()].map(bytes => bytes.toString()));
  assert.deepEqual(requests, completeCounts, 'Completed store must not request image bytes again');
  await page.waitForTimeout(2300);
  assert.equal(insertions + await page.evaluate(() => window.progressPanels), 0, 'Completed downloads must not flash a progress panel');
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
  console.log('PASS: failed worker setup recovers; no response clones; at most two downloads; game starts after saved bytes; resume/offline/delta updates preserve progress and saves.');
})().finally(async () => {
  if (context) await context.close();
  server.close();
  fs.rmSync(profile, {recursive: true, force: true});
}).catch(error => {console.error(error); process.exitCode = 1;});

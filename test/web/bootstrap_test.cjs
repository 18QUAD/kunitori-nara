const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('web/flutter_bootstrap.js', 'utf8')
  .replace('{{flutter_js}}', '')
  .replace('{{flutter_build_config}}', '')
  .replaceAll('{{flutter_service_worker_version}}', 'test-build-90');

async function run(serviceWorker, top = 0, safeTop = 0) {
  let loaded = 0, reloaded = 0;
  const buildConfig = {builds: [{mainJsPath: 'main.dart.js'}]};
  const host = {
    addEventListener() {},
    getBoundingClientRect() {return {top, bottom: 800};},
  };
  const context = {
    URL, console: {warn() {}},
    document: {
      baseURI: 'https://18quad.github.io/kunitori-nara/',
      getElementById() {return host;}, addEventListener() {},
    },
    navigator: serviceWorker ? {serviceWorker} : {},
    window: {
      location: {reload() { reloaded++; }}, innerHeight: 800,
      addEventListener() {}, dispatchEvent() {},
    },
    getComputedStyle() {return {paddingTop: `${safeTop}px`, paddingBottom: '0px'};},
    ResizeObserver: class {observe() {}},
    Event: class {},
    _flutter: {buildConfig, loader: {load() { loaded++; }}},
  };
  await vm.runInNewContext(source, context);
  assert.equal(buildConfig.builds[0].mainJsPath, 'main.dart.js?v=test-build-90');
  assert.equal(context.window.kunitoriViewport.top(), Math.max(0, safeTop - top));
  return {loaded, reloaded};
}

(async () => {
  assert.deepEqual(await run(), {loaded: 1, reloaded: 0});
  assert.deepEqual(await run(undefined, 0, 44), {loaded: 1, reloaded: 0});
  assert.deepEqual(await run(undefined, 80, 44), {loaded: 1, reloaded: 0});
  // Worker registration/migration belongs to map-cache.js. Bootstrap must not
  // unregister a persistent map store or force a reload on each visit.
  assert.deepEqual(await run({
    controller: {scriptURL: 'https://18quad.github.io/kunitori-nara/map-cache-worker.js?v=current'},
    async getRegistrations() {throw new Error('Bootstrap must not enumerate or unregister workers');},
  }), {loaded: 1, reloaded: 0});
  console.log('Bootstrap checks passed: versioned entrypoint and no worker removal or forced reload.');
})().catch(error => {console.error(error); process.exitCode = 1;});

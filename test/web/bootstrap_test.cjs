const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('web/flutter_bootstrap.js', 'utf8')
  .replace('{{flutter_js}}', '')
  .replace('{{flutter_build_config}}', '')
  .replaceAll('{{flutter_service_worker_version}}', 'test-build-90');

async function run(serviceWorker) {
  let loaded = 0, reloaded = 0;
  const listeners = {};
  const buildConfig = {builds: [{mainJsPath: 'main.dart.js'}]};
  const host = {
    style: {},
    addEventListener() {},
    getBoundingClientRect() {return {top: 0, bottom: 800};},
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
      addEventListener(name, callback) {listeners[name] = callback;}, dispatchEvent() {},
    },
    getComputedStyle() {return {paddingTop: '0px', paddingBottom: '0px'};},
    ResizeObserver: class {observe() {}},
    Event: class {},
    _flutter: {buildConfig, loader: {load() { loaded++; }}},
  };
  await vm.runInNewContext(source, context);
  assert.equal(host.style.height, '800px');
  // A stale host rectangle and a scrolled viewport must not become game padding.
  context.window.visualViewport = {offsetTop: 24, height: 390};
  listeners.resize();
  assert.equal(host.style.height, '390px');
  assert.equal(host.style.top, '24px');
  assert.equal(context.window.kunitoriViewport.top(), 0);
  assert.equal(context.window.kunitoriViewport.bottom(), 0);
  context.window.visualViewport = {offsetTop: 0, height: 844};
  listeners.resize();
  assert.equal(host.style.height, '844px');
  assert.equal(host.style.top, '0px');
  assert.equal(buildConfig.builds[0].mainJsPath, 'main.dart.js?v=test-build-90');
  return {loaded, reloaded};
}

(async () => {
  assert.deepEqual(await run(), {loaded: 1, reloaded: 0});
  let unregistered = 0, unrelated = 0;
  const own = {scope: 'https://18quad.github.io/kunitori-nara/',
    async unregister() {unregistered++; return true;}};
  const other = {scope: 'https://18quad.github.io/other/',
    async unregister() {unrelated++; return true;}};
  assert.deepEqual(await run({
    controller: {scriptURL: 'https://18quad.github.io/kunitori-nara/flutter_service_worker.js?v=old'},
    async getRegistrations() {return [own, other];},
  }), {loaded: 0, reloaded: 1});
  assert.equal(unregistered, 1);
  assert.equal(unrelated, 0);
  assert.deepEqual(await run({controller: null,
    async getRegistrations() {return [];},
  }), {loaded: 1, reloaded: 0});
  assert.deepEqual(await run({
    async getRegistrations() {throw new Error('unavailable');},
  }), {loaded: 1, reloaded: 0});
  console.log('Bootstrap checks passed: versioned entrypoint, legacy migration, unrelated scope, fresh load, failure fallback.');
})().catch(error => {console.error(error); process.exitCode = 1;});

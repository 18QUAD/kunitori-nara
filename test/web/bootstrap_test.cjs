const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('web/flutter_bootstrap.js', 'utf8')
  .replace('{{flutter_js}}', '')
  .replace('{{flutter_build_config}}', '')
  .replaceAll('{{flutter_service_worker_version}}', 'test-build-90');

async function run(serviceWorker) {
  let loaded = 0, reloaded = 0;
  const buildConfig = {builds: [{mainJsPath: 'main.dart.js'}]};
  const context = {
    URL, console: {warn() {}},
    document: {baseURI: 'https://18quad.github.io/kunitori-nara/'},
    navigator: serviceWorker ? {serviceWorker} : {},
    window: {location: {reload() { reloaded++; }}},
    _flutter: {buildConfig, loader: {load() { loaded++; }}},
  };
  await vm.runInNewContext(source, context);
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

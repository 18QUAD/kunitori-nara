const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

async function scenario(scope = 'https://example.test/game/') {
  let now = 0, sequence = 0, registrations = 0, unregisters = 0, finished = false;
  const timers = new Map(), records = [], elements = new Map();
  const schedule = (fn, delay) => {const id = ++sequence; timers.set(id, {fn, at: now + delay}); return id;};
  const flush = async () => {for (let i = 0; i < 30; i++) await Promise.resolve();};
  const advance = async target => {
    while (true) {
      const entry = [...timers].filter(([, t]) => t.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
      if (!entry) break;
      now = entry[1].at; timers.delete(entry[0]); entry[1].fn(); await flush();
    }
    now = target; await flush();
  };
  function element() {
    const children = [];
    return {setAttribute(){}, removeAttribute(){}, append(...items){children.push(...items);},
      querySelector(tag){return children.find(child => child.tag === tag);}, remove(){},
      set id(value){elements.set(value, this);}};
  }
  const document = new EventTarget();
  Object.assign(document, {baseURI: 'https://example.test/game/', currentScript: {src:'https://example.test/game/map-cache.js?v=regression'}, hidden:false,
    createElement(tag){return Object.assign(element(), {tag});}, getElementById(id){return elements.get(id);},
    body: {insertBefore(){}, setAttribute(){}, removeAttribute(){}}});
  const workerURL = 'https://example.test/game/map-cache-worker.js?v=regression';
  const sw = new EventTarget();
  sw.register = async () => {
    registrations++;
    if (registrations === 1) {
      const pending = Object.assign(new EventTarget(), {state:'activating', scriptURL:workerURL});
      return {scope, installing:pending, unregister:async () => {unregisters++; return true;}};
    }
    sw.controller = {scriptURL:workerURL, postMessage(message, ports){ports[0].answer({done:true,saved:10,total:10,savedBytes:100,bytes:100});}};
    return {scope, active:sw.controller};
  };
  class Channel {
    constructor(){this.port1 = {close(){}}; this.port2 = {answer:data => this.port1.onmessage({data})};}
  }
  const window = new EventTarget();
  window.kunitoriDiagnostics = {record: event => records.push(event)};
  const context = {window, document, navigator:{serviceWorker:sw,onLine:true}, URL, MessageChannel:Channel,
    setInterval:()=>0, setTimeout:schedule, clearTimeout:id=>timers.delete(id)};
  vm.runInNewContext(fs.readFileSync('web/map-cache.js','utf8'), context);
  window.kunitoriMapDownload.then(() => {finished = true;});
  await flush();
  await advance(15000); // Safari worker activation hangs until timeout.
  assert(records.includes('map_storage_setup_retry'));
  document.hidden = true;
  document.dispatchEvent(new Event('visibilitychange')); // Used to cancel the sole setup retry.
  await advance(17000);
  assert.equal(registrations, 2, 'Hidden event must not cancel initialization recovery');
  document.hidden = false;
  document.dispatchEvent(new Event('visibilitychange'));
  await flush();
  assert(finished, 'Full storage completion must release startup gate after recovery');
  return {unregisters, records};
}

test('stuck activation recovers across visibility changes without clearing saved data', async () => {
  const result = await scenario();
  assert.equal(result.unregisters, 1);
  assert(result.records.includes('map_storage_registration_recovered'));
});
test('recovery never unregisters a different scope', async () => {
  const result = await scenario('https://example.test/');
  assert.equal(result.unregisters, 0);
});

/* Silent, resumable initial download; never decode or display an image here. */
'use strict';
window.kunitoriMapStorage = (async () => {
  if (!('serviceWorker' in navigator)) return;
  const root = new URL('./', document.baseURI);
  const version = new URL(document.currentScript.src).searchParams.get('v') || '1';
  const worker = new URL(`map-cache-worker.js?v=${encodeURIComponent(version)}`, root);
  try {
    const registration = await navigator.serviceWorker.register(worker, {scope: root.href, updateViaCache: 'none'});
    const pending = registration.installing || registration.waiting;
    if (pending && pending.state !== 'activated') {
      await new Promise((resolve, reject) => {
        const changed = () => {
          if (pending.state === 'activated') resolve();
          if (pending.state === 'redundant') reject(new Error('Map worker installation failed'));
        };
        pending.addEventListener('statechange', changed);
        changed();
      });
    }
    await navigator.serviceWorker.ready;
    if (!navigator.serviceWorker.controller ||
        new URL(navigator.serviceWorker.controller.scriptURL).pathname !== worker.pathname) {
      await new Promise(resolve => {
        const changed = () => {
          if (navigator.serviceWorker.controller &&
              new URL(navigator.serviceWorker.controller.scriptURL).pathname === worker.pathname) {
            navigator.serviceWorker.removeEventListener('controllerchange', changed);
            resolve();
          }
        };
        navigator.serviceWorker.addEventListener('controllerchange', changed);
        changed();
      });
    }
    // A refusal doesn't prevent ordinary persistent CacheStorage from working.
    navigator.storage?.persist?.().catch(() => {});
    let retry = 1000;
    let running = false;
    let done = false;
    let timer;
    async function next() {
      clearTimeout(timer);
      if (done || running || document.hidden || !navigator.onLine) return;
      running = true;
      try {
        const result = await new Promise((resolve, reject) => {
          const channel = new MessageChannel();
          const timeout = setTimeout(() => {channel.port1.close(); reject(new Error('Map storage batch timeout'));}, 90000);
          channel.port1.onmessage = event => {
            clearTimeout(timeout);
            channel.port1.close();
            event.data.error ? reject(new Error(event.data.error)) : resolve(event.data);
          };
          navigator.serviceWorker.controller.postMessage({type: 'warm-map-images'}, [channel.port2]);
        });
        done = result.done;
        if (done) window.kunitoriDiagnostics?.record?.('map_storage_complete', JSON.stringify({}));
        retry = 1000;
        if (!done) timer = setTimeout(next, 50);
      } catch (error) {
        window.kunitoriDiagnostics?.record?.('map_storage_retry', JSON.stringify({error: String(error)}));
        timer = setTimeout(next, retry);
        retry = Math.min(retry * 2, 30000);
      } finally {running = false;}
    }
    window.addEventListener('online', next);
    document.addEventListener('visibilitychange', next);
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      done = false;
      next();
    });
    // Start after the game has had a chance to request its visible map first.
    window.kunitoriDiagnostics?.record?.('map_storage_start', JSON.stringify({}));
    timer = setTimeout(next, 2000);
  } catch (error) {
    // No save data, unrelated workers, or caches are removed on failure.
    console.warn('Local map storage unavailable:', error);
  }
})();

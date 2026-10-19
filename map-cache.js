/* Resumable initial download; never decode an image while saving it to disk. */
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
    let lastProgress;
    let panel;
    let panelObserver;
    function showProgress(result, waiting = false) {
      if (result) lastProgress = result;
      if (lastProgress?.done) {
        panelObserver?.disconnect();
        panel?.remove();
        panel = null;
        document.documentElement.style.setProperty('--map-download-height', '0px');
        return;
      }
      if (!panel) {
        panel = document.createElement('aside');
        panel.id = 'map-download-status';
        panel.setAttribute('aria-label', '地図データのダウンロード状況');
        const title = document.createElement('p');
        title.textContent = '全国の地図データをダウンロード中';
        const bar = document.createElement('progress');
        bar.max = 100;
        bar.setAttribute('aria-label', '地図データのダウンロード');
        const detail = document.createElement('small');
        panel.append(title, bar, detail);
        document.body.insertBefore(panel, document.getElementById('app-host') || document.body.firstChild);
        panelObserver = new ResizeObserver(() => {
          if (panel) document.documentElement.style.setProperty('--map-download-height', `${panel.offsetHeight}px`);
        });
        panelObserver.observe(panel);
      }
      const bar = panel.querySelector('progress');
      const detail = panel.querySelector('small');
      if (lastProgress?.bytes > 0) {
        const percent = Math.min(100, Math.floor(lastProgress.savedBytes / lastProgress.bytes * 100));
        bar.value = lastProgress.savedBytes / lastProgress.bytes * 100;
        detail.textContent = `初回保存 · ${(lastProgress.savedBytes / 1e6).toFixed(1)} / ${(lastProgress.bytes / 1e6).toFixed(1)} MB（${percent}%）`;
      } else {
        bar.removeAttribute('value');
        detail.textContent = '初回ダウンロードを準備しています';
      }
      panel.querySelector('p').textContent = waiting
        ? (navigator.onLine ? '地図データのダウンロードを再開しています' : '接続を待っています。続きから再開します')
        : '全国の地図データをダウンロード中';
      document.documentElement.style.setProperty('--map-download-height', `${panel.offsetHeight}px`);
    }
    function request(type) {
      return new Promise((resolve, reject) => {
        const channel = new MessageChannel();
        const timeout = setTimeout(() => {channel.port1.close(); reject(new Error('Map storage batch timeout'));}, 90000);
        channel.port1.onmessage = event => {
          clearTimeout(timeout);
          channel.port1.close();
          event.data.error ? reject(new Error(event.data.error)) : resolve(event.data);
        };
        navigator.serviceWorker.controller.postMessage({type}, [channel.port2]);
      });
    }
    async function next() {
      clearTimeout(timer);
      if (done || running || document.hidden || !navigator.onLine) return;
      running = true;
      try {
        const result = await request('warm-map-images');
        done = result.done;
        showProgress(result);
        if (done) window.kunitoriDiagnostics?.record?.('map_storage_complete', JSON.stringify({}));
        retry = 1000;
        if (!done) timer = setTimeout(next, 50);
      } catch (error) {
        showProgress(null, true);
        window.kunitoriDiagnostics?.record?.('map_storage_retry', JSON.stringify({error: String(error)}));
        timer = setTimeout(next, retry);
        retry = Math.min(retry * 2, 30000);
      } finally {running = false;}
    }
    window.addEventListener('online', next);
    window.addEventListener('offline', () => {if (lastProgress && !done) showProgress(null, true);});
    document.addEventListener('visibilitychange', next);
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      done = false;
      next();
    });
    // Read the saved cursor before starting work: resumed downloads keep their
    // percentage, and completed downloads never flash a new progress panel.
    request('map-images-status').then(result => {
      if (!running && (!lastProgress || result.saved >= lastProgress.saved)) {
        done = result.done;
        showProgress(result, !navigator.onLine);
      }
    }).catch(() => showProgress(null, true));
    // Start after the game has had a chance to request its visible map first.
    window.kunitoriDiagnostics?.record?.('map_storage_start', JSON.stringify({}));
    timer = setTimeout(next, 2000);
  } catch (error) {
    // No save data, unrelated workers, or caches are removed on failure.
    console.warn('Local map storage unavailable:', error);
  }
})();

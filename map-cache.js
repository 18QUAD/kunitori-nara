/* Resumable initial download; never decode an image while saving it to disk. */
'use strict';
let finishMapDownload;
window.kunitoriMapDownload = new Promise(resolve => {finishMapDownload = resolve;});
window.kunitoriMapStorage = (async () => {
  if (!('serviceWorker' in navigator)) {finishMapDownload(); return;}
  const root = new URL('./', document.baseURI);
  const version = new URL(document.currentScript.src).searchParams.get('v') || '1';
  const worker = new URL(`map-cache-worker.js?v=${encodeURIComponent(version)}`, root);
  let retry = 1000;
  let running = false;
  let connected = false;
  let done = false;
  let setupTimer;
  let downloadTimer;
  let connecting = false;
  let setupAttempts = 0;
  let lastProgress;
  let panel;

  function showProgress(result, waiting = false) {
    if (result) lastProgress = result;
    if (lastProgress?.done) {
      panel?.remove();
      panel = null;
      document.body.removeAttribute('data-map-loading');
      return;
    }
    if (!panel) {
      panel = document.createElement('aside');
      panel.id = 'map-download-status';
      panel.setAttribute('aria-label', '地図データのダウンロード状況');
      const title = document.createElement('p');
      title.textContent = '保存済みデータを確認しています';
      const bar = document.createElement('progress');
      bar.max = 100;
      bar.setAttribute('aria-label', '地図データのダウンロード');
      const detail = document.createElement('small');
      const note = document.createElement('small');
      note.textContent = '保存完了後にゲームを開始します';
      panel.append(title, bar, detail, note);
      document.body.insertBefore(panel, document.getElementById('app-host') || document.body.firstChild);
      document.body.setAttribute('data-map-loading', '');
    }
    const bar = panel.querySelector('progress');
    const detail = panel.querySelector('small');
    if (lastProgress?.bytes > 0) {
      const percent = Math.min(100, Math.floor(lastProgress.savedBytes / lastProgress.bytes * 100));
      bar.value = lastProgress.savedBytes / lastProgress.bytes * 100;
      detail.textContent = `データ保存 · ${(lastProgress.savedBytes / 1e6).toFixed(1)} / ${(lastProgress.bytes / 1e6).toFixed(1)} MB（${percent}%）`;
    } else {
      bar.removeAttribute('value');
      detail.textContent = setupAttempts > 1
        ? `保存処理を復旧しています（再試行 ${setupAttempts - 1} 回）`
        : '保存済みデータを確認しています';
    }
    panel.querySelector('p').textContent = waiting
      ? (navigator.onLine ? '地図データのダウンロードを再開しています' : '接続を待っています。続きから再開します')
      : (lastProgress ? '地図・ゲームデータを端末に保存中' : '保存済みデータを確認しています');
  }
  function request(type, data = {}, timeoutMs = 90000) {
    return new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      const timeout = setTimeout(() => {channel.port1.close(); reject(new Error(`Map storage ${type} timeout`));}, timeoutMs);
      channel.port1.onmessage = event => {
        clearTimeout(timeout);
        channel.port1.close();
        event.data.error ? reject(new Error(event.data.error)) : resolve(event.data);
      };
      try {
        navigator.serviceWorker.controller.postMessage({type, ...data}, [channel.port2]);
      } catch (error) {
        clearTimeout(timeout);
        channel.port1.close();
        reject(error);
      }
    });
  }
  async function next() {
    if (!connected || done || running || document.hidden || !navigator.onLine) return;
    clearTimeout(downloadTimer);
    running = true;
    try {
      const result = await request('warm-map-images');
      done = result.done;
      showProgress(result);
      
      if (done) {finishMapDownload(); }
      retry = 1000;
      if (!done) downloadTimer = setTimeout(next, 0);
    } catch (error) {
      // A failed window can still have committed a verified prefix. Show that
      // progress during the retry delay instead of appearing stuck at zero.
      try {
        const saved = await request('map-images-status');
        showProgress(saved, true);
        
      } catch (_) {showProgress(null, true);}
      
      downloadTimer = setTimeout(next, retry);
      retry = Math.min(retry * 2, 30000);
    } finally {running = false;}
  }
  window.kunitoriMapMemory = {
    async get() {
      await window.kunitoriMapStorage;
      return (await request('map-memory-get')).megabytes;
    },
    async release() {
      await window.kunitoriMapStorage;
      const memory = await request('map-memory-release');
      
      return memory.bytes;
    },
    async set(megabytes) {
      await window.kunitoriMapStorage;
      const memory = await request('map-memory-set', {megabytes});
      
      return memory.megabytes;
    },
  };
  function bounded(operation, phase) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(`Map worker ${phase} timed out`)), 15000);
      operation.then(value => {clearTimeout(timeout); resolve(value);}, error => {clearTimeout(timeout); reject(error);});
    });
  }
  function controlled() {
    const script = navigator.serviceWorker.controller?.scriptURL;
    if (!script) return false;
    const active = new URL(script);
    return active.origin === worker.origin && active.pathname === worker.pathname && active.search === worker.search;
  }
  async function connect() {
    if (connecting || connected || done) return;
    clearTimeout(setupTimer);
    connecting = true;
    setupAttempts++;
    if (panel) showProgress(null, true);
    let registration;
    let phase = 'registration';
    try {
      
      const existing = await navigator.serviceWorker.getRegistration?.(root.href);
      registration = existing?.active?.scriptURL === worker.href && !existing.installing && !existing.waiting
        ? existing
        : await bounded(navigator.serviceWorker.register(worker, {scope: root.href, updateViaCache: 'none'}), 'registration');
      if (existing === registration && navigator.onLine && registration.update) {
        try {await bounded(registration.update(), 'update');} catch (_) {}
      }
      
      phase = 'activation';
      const pending = registration.installing || registration.waiting;
      if (pending && pending.state !== 'activated') {
        await new Promise((resolve, reject) => {
          const timeout = setTimeout(() => finish(new Error('Map worker activation timed out')), 15000);
          function finish(error) {
            clearTimeout(timeout);
            pending.removeEventListener('statechange', changed);
            error ? reject(error) : resolve();
          }
          function changed() {
            if (pending.state === 'activated') finish();
            if (pending.state === 'redundant') finish(new Error('Map worker installation failed'));
          }
          pending.addEventListener('statechange', changed);
          changed();
        });
      }
      
      phase = 'control';
      if (!controlled()) {
        await new Promise((resolve, reject) => {
          const timeout = setTimeout(() => finish(new Error('Map worker control timed out')), 15000);
          function finish(error) {
            clearTimeout(timeout);
            navigator.serviceWorker.removeEventListener('controllerchange', changed);
            error ? reject(error) : resolve();
          }
          function changed() {if (controlled()) finish();}
          navigator.serviceWorker.addEventListener('controllerchange', changed);
          changed();
        });
      }
      
      phase = 'identity';
      const identity = await request('map-runtime-version', {}, 15000);
      if (identity.build && identity.build !== version) {
        // An old cached document may install a newer worker. Do not start its
        // old bootstrap against new data. The worker serves this pinned entry
        // from the verified current runtime, even when the HTTP cache is stale.
        
        const current = new URL(root);
        current.searchParams.set('app-build', identity.build);
        window.location.replace(current.href);
        return;
      }
      // Control alone is not a usable connection: failed identity requests must
      // leave connect() retryable, otherwise its own guard strands startup.
      connected = true;
      navigator.storage?.persist?.().catch(() => {});
      // Read the saved cursor before starting work: resumed downloads keep their
      // percentage, and completed downloads never flash a new progress panel.
      await request('map-images-status').then(result => {
        if (!running && (!lastProgress || result.saved >= lastProgress.saved)) {
          done = result.done;
          showProgress(result, !navigator.onLine);
          
          if (done) finishMapDownload();
        }
      }).catch(error => {
        
        if (!done) showProgress(null, true);
      });
      // The game engine starts only after the initial disk store is complete.
      
      if (!done) downloadTimer = setTimeout(next, 0);
    } catch (error) {
      connected = false;
      
      // An old worker can remain stuck on extended events. Replace only this
      // app's registration; its disk cache and all game saves remain intact.
      if (registration && phase !== 'registration' && registration.scope === root.href) {
        const scripts = [registration.installing, registration.waiting, registration.active].filter(Boolean);
        if (scripts.length && scripts.every(item => {
          const url = new URL(item.scriptURL);
          return url.origin === worker.origin && url.pathname === worker.pathname;
        })) {
          try {
            await bounded(registration.unregister(), 'recovery');
            
          } catch (recoveryError) {
            
          }
        }
      }
      showProgress(null, true);
      setupTimer = setTimeout(connect, retry);
      retry = Math.min(retry * 2, 30000);
    } finally {connecting = false;}
  }
  function resume() {
    if (document.hidden || !navigator.onLine) return;
    if (connected) next();
    else connect();
  }
  window.addEventListener('online', resume);
  window.addEventListener('offline', () => {if (lastProgress && !done) showProgress(null, true);});
  document.addEventListener('visibilitychange', resume);
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!done) resume();
  });
  setTimeout(() => {if (!lastProgress && !done) showProgress(null);}, 500);
  return connect();
})();

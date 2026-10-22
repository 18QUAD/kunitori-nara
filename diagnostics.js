// Small, synchronous checkpoints survive renderer termination without an unload callback.
// This is evidence of the last observed state, never a diagnosis of an OS memory kill.
(() => {
  'use strict';
  const key = 'kunitori.diagnostics.v1', tabKey = key + '.tab';
  const traceKey = key + '.trace';
  let traces = [], traceSequence = 0;
  const maxBytes = 96 * 1024, maxEvents = 64, maxSessions = 3;
  let storageAvailable = true, state = {}, lastWrite = 0, ended = false;
  const id = () => Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 12);
  let tab = id(), previousId;
  try {
    previousId = sessionStorage.getItem(tabKey);
  } catch (_) {}
  const run = id();
  try { sessionStorage.setItem(tabKey, run); } catch (_) {}
  const read = () => {
    try {
      const raw = localStorage.getItem(key);
      if (!raw || raw.length > maxBytes) return [];
      const parsed = JSON.parse(raw);
      const sessions = Array.isArray(parsed.sessions) ? parsed.sessions.slice(-maxSessions) : [];
      // Compact stage checkpoints are independent of the throttled full state log.
      // Merge them before the next startup overwrites the checkpoint slot.
      try {
        const rawTrace = localStorage.getItem(traceKey);
        if (rawTrace && rawTrace.length <= 12 * 1024) {
          const saved = JSON.parse(rawTrace);
          const owner = sessions.find(s => s.id === saved.session);
          if (owner && Array.isArray(saved.events)) {
            const seen = new Set(owner.events.map(e => e.traceSequence).filter(Number.isFinite));
            owner.events.push(...saved.events.filter(e => Number.isFinite(e.traceSequence) && !seen.has(e.traceSequence)));
            owner.events.sort((a,b) => a.at.localeCompare(b.at) || (a.traceSequence || 0) - (b.traceSequence || 0));
            owner.events = owner.events.slice(-maxEvents);
          }
        }
      } catch (_) {}
      return sessions;
    } catch (_) { return []; }
  };
  const previous = read().find(s => s.id === previousId);
  // Only associate a predecessor from this tab, never another tab's open session.
  const session = {
    id: run, tab: previous?.tab || tab, build: 'attack-contact-recovery-20261022-v1',
    startedAt: new Date().toISOString(),
    navigation: performance.getEntriesByType?.('navigation')?.[0]?.type || 'unknown',
    wasDiscarded: document.wasDiscarded === true,
    previousSession: previous?.id || null,
    previousEnd: previous ? (previous.ended ? 'pagehide_observed' : 'no_pagehide_observed') : null,
    userAgent: navigator.userAgent.slice(0, 256), events: [],
  };
  function clean(value, depth = 0) {
    if (value == null || typeof value === 'boolean') return value;
    if (typeof value === 'number') return Number.isFinite(value) ? value : null;
    if (typeof value === 'string') return value.slice(0, 240);
    if (typeof value !== 'object' || depth > 2) return null;
    const out = {};
    for (const k of Object.keys(value).slice(0, 32)) out[k.slice(0, 48)] = clean(value[k], depth + 1);
    return out;
  }
  function memory() {
    const m = performance.memory;
    return {
      jsUsedBytes: m?.usedJSHeapSize ?? null,
      jsTotalBytes: m?.totalJSHeapSize ?? null,
      jsLimitBytes: m?.jsHeapSizeLimit ?? null,
      canvasKitHeapBytes: window.flutterCanvasKit?.HEAPU8?.buffer?.byteLength ?? null,
      // Browser APIs cannot report total process/GPU memory, especially on iOS.
      processBytes: null,
    };
  }
  function persist() {
    try {
      let sessions = read().filter(s => s.id !== run);
      sessions.push(session);
      sessions = sessions.slice(-maxSessions);
      let text = JSON.stringify({version: 1, sessions});
      while (text.length > maxBytes / 2) {
        // Preserve earlier runs too: trim events, rather than losing the crash run
        // as soon as the new healthy run fills its own ring.
        const longest = sessions.reduce((a, b) => a.events.length > b.events.length ? a : b);
        if (longest.events.length > 4) longest.events.shift();
        else if (sessions.length > 1) sessions.shift();
        else break;
        text = JSON.stringify({version: 1, sessions});
      }
      localStorage.setItem(key, text);
      storageAvailable = true;
    } catch (_) { storageAvailable = false; }
  }
  function checkpoint(event, data) {
    try {
      const at = new Date().toISOString();
      const entry = {at, event: String(event).slice(0,80), traceSequence: ++traceSequence,
        visibility: document.visibilityState, state: clean(data || {}), memory: memory()};
      traces.push(entry);
      traces = traces.slice(-24);
      let text = JSON.stringify({session:run,events:traces});
      while (text.length > 6 * 1024 && traces.length > 1) {
        traces.shift(); text = JSON.stringify({session:run,events:traces});
      }
      localStorage.setItem(traceKey,text);
    } catch (_) { /* A failed checkpoint must never break an action. */ }
  }
  function record(event, data, important = true) {
    try {
      if (String(event).startsWith('trace_')) {checkpoint(event,data);return;}
      if (event === 'flutter_start' && typeof data?.appBuild === 'string') session.build = data.appBuild;
      if (data) {
        const sanitized = clean(data);
        // Error stacks are bounded separately and must not pollute every later heartbeat.
        state = {...state, ...sanitized};
        if (typeof data.stack === 'string') state.stack = data.stack.slice(0,4096);
        if (typeof data.error === 'string') state.error = data.error.slice(0,1024);
      }
      const now = Date.now();
      if (!important && now - lastWrite < 1000) return;
      lastWrite = now;
      session.ended = ended;
      session.events.push({at: new Date(now).toISOString(), event: String(event).slice(0, 80),
        visibility: document.visibilityState, state: {...state}, memory: memory()});
      session.events = session.events.slice(-maxEvents);
      persist();
      delete state.stack;
      delete state.context;
      delete state.library;
    } catch (_) { /* Diagnostics must never interfere with the game. */ }
  }
  function report() {
    record('export');
    return JSON.stringify({
      version: 1, exportedAt: new Date().toISOString(), storageAvailable, lastUploaded,
      explanation: 'no_pagehide_observed means a termination callback was not recorded; it does not prove a memory kill. null means unavailable. canvasKitHeapBytes is WASM capacity, not total process memory.',
      currentSession: run, sessions: read(),
    }, null, 2);
  }
  // Recover existing local-only logs as well. Never block the map on telemetry.
  const endpoint = 'https://kunitori-nara-regional-ads.narusaki-masafumi.workers.dev/diagnostics';
  let sending = false, lastUploaded = null, clientId;
  try {
    clientId = localStorage.getItem(key + '.client');
    if (!/^[a-zA-Z0-9-]{16,80}$/.test(clientId || '')) {
      clientId = id() + '-' + id(); localStorage.setItem(key + '.client', clientId);
    }
  } catch (_) {}
  async function upload() {
    if (sending || !clientId || typeof fetch !== 'function' || navigator.onLine === false) return;
    const sessions = read();
    if (!sessions.length) return;
    let body = JSON.stringify({version:1,clientId,sessions});
    while (new TextEncoder().encode(body).length > 40 * 1024) {
      const longest = sessions.reduce((a,b)=>a.events.length>b.events.length?a:b);
      if(longest.events.length>4)longest.events.shift();else if(sessions.length>1)sessions.shift();else return;
      body = JSON.stringify({version:1,clientId,sessions});
    }
    sending = true;
    const controller = new AbortController();
    const timeout = setTimeout(()=>controller.abort(),10000);
    try {
      const response = await fetch(endpoint,{method:'POST',mode:'cors',credentials:'omit',cache:'no-store',
        headers:{'Content-Type':'text/plain;charset=UTF-8'},body,keepalive:true,signal:controller.signal});
      if(response.ok)lastUploaded = new Date().toISOString();
    } catch (_) { /* Offline reports remain local for the next retry. */ }
    finally {clearTimeout(timeout);sending=false;}
  }
  window.kunitoriDiagnostics = {
    record(event, json, important) {
      try { record(event, JSON.parse(json), important); } catch (_) {}
    },
    report,
    upload,
    download() {
      try {
        const url = URL.createObjectURL(new Blob([report()], {type: 'application/json'}));
        const a = document.createElement('a');
        a.href = url; a.download = 'kunitori-diagnostics-' + Date.now() + '.json';
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 30000);
      } catch (_) {}
    },
  };
  window.addEventListener('pagehide', e => { ended = true; record('pagehide', {persisted: e.persisted}); });
  window.addEventListener('pageshow', e => { ended = false; record('pageshow', {persisted: e.persisted}); });
  document.addEventListener('visibilitychange', () => {record('visibilitychange');if(document.visibilityState==='hidden')void upload();});
  window.addEventListener('online', () => {void upload();});
  for (const type of ['webglcontextlost','webglcontextrestored','contextlost','contextrestored']) {
    document.addEventListener(type, () => record(type), true);
  }
  window.addEventListener('error', e => record('browser_error', {
    error: e.message || 'resource_load_error', stack: e.error?.stack,
    resource: safeResource(e.filename || e.target?.src || e.target?.href),
    line: e.lineno, column: e.colno,
  }), true);
  window.addEventListener('unhandledrejection', e => record('unhandled_rejection', {
    error: String(e.reason?.message || e.reason || 'unknown'), stack: e.reason?.stack,
  }));
  function safeResource(value) {
    if (!value) return null;
    try {const u = new URL(value,document.baseURI);return u.pathname;} catch (_) {return String(value).split(/[?#]/)[0];}
  }
  let lastBrowserFrame = null, lastFrameCheckpoint = 0, lastTick = Date.now(), lastVisibility = document.visibilityState;
  if (typeof requestAnimationFrame === 'function') {
    const frame = () => {
      if (!ended && document.visibilityState === 'visible') {
        lastBrowserFrame = Date.now();
        if (lastBrowserFrame - lastFrameCheckpoint >= 5000) {
          lastFrameCheckpoint = lastBrowserFrame;
          record('browser_frame', {lastBrowserFrame}, false);
        }
      }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }
  setInterval(() => {
    const now = Date.now(), visible = document.visibilityState;
    if (!ended && visible === 'visible' && lastVisibility === 'visible' && now - lastTick > 2500) {
      record('event_loop_delay', {delayMs: now-lastTick-1000, lastBrowserFrame});
    }
    lastTick = now; lastVisibility = visible;
  },1000);
  setInterval(() => { if (!ended && document.visibilityState === 'visible') record('heartbeat'); }, 5000);
  record('startup');
  setTimeout(()=>{void upload();},2000);
  setInterval(()=>{if(!ended && document.visibilityState==='visible')void upload();},60000);
})();

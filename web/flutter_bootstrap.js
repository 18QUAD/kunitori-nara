{{flutter_js}}
{{flutter_build_config}}
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?v={{flutter_service_worker_version}}';
  }
}
// Embed in the document rather than making body a fixed, non-scrolling surface.
// The large viewport provides real page pixels behind floating browser controls.
const appHost = document.getElementById('app-host');
// Keep native selection menus off game controls; editing retains its normal menu.
for (const type of ['selectstart', 'contextmenu']) {
  appHost.addEventListener(type, (event) => {
    if (!event.target.closest?.('input, textarea, [contenteditable="true"]')) {
      event.preventDefault();
    }
  });
}
const safeAreaProbe = document.getElementById('safe-area-probe');
let topInset = 0;
let bottomInset = 0;
function updateBrowserViewport() {
  const rect = appHost.getBoundingClientRect();
  const viewport = window.visualViewport;
  const visibleTop = viewport ? viewport.offsetTop : 0;
  const visibleHeight = viewport ? viewport.height : window.innerHeight;
  const safeArea = getComputedStyle(safeAreaProbe);
  const nextTop = Math.max(0, visibleTop - rect.top, parseFloat(safeArea.paddingTop) || 0);
  const nextBottom = Math.max(0, rect.bottom - visibleTop - visibleHeight, parseFloat(safeArea.paddingBottom) || 0);
  if (nextTop !== topInset || nextBottom !== bottomInset) {
    topInset = nextTop;
    bottomInset = nextBottom;
    window.dispatchEvent(new Event('kunitori-viewport'));
  }
}
window.kunitoriViewport = {top: () => topInset, bottom: () => bottomInset};
window.addEventListener('resize', updateBrowserViewport, {passive: true});
window.addEventListener('scroll', updateBrowserViewport, {passive: true});
window.visualViewport?.addEventListener('resize', updateBrowserViewport, {passive: true});
window.visualViewport?.addEventListener('scroll', updateBrowserViewport, {passive: true});
new ResizeObserver(updateBrowserViewport).observe(appHost);
updateBrowserViewport();

async function startCurrentBuild() {
  // Retire only this app's legacy worker. Keep localStorage/IndexedDB saves.
  if ('serviceWorker' in navigator) {
    const scope = new URL('.', document.baseURI).href;
    const workerUrl = new URL('flutter_service_worker.js', scope);
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      const controller = navigator.serviceWorker.controller;
      const controlledByLegacyWorker = controller &&
        new URL(controller.scriptURL).pathname === workerUrl.pathname;
      let retired = false;
      for (const registration of registrations) {
        if (registration.scope === scope) {
          retired = await registration.unregister() || retired;
        }
      }
      if (retired && controlledByLegacyWorker) {
        window.location.reload();
        return;
      }
    } catch (error) {
      console.warn('Could not retire legacy app worker:', error);
    }
  }
  return _flutter.loader.load({
    config: {canvasKitBaseUrl: 'canvaskit/'},
    onEntrypointLoaded: async (engineInitializer) => {
      const appRunner = await engineInitializer.initializeEngine({hostElement: appHost});
      await appRunner.runApp();
    },
  });
}
startCurrentBuild();

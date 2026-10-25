{{flutter_js}}
{{flutter_build_config}}
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?v={{flutter_service_worker_version}}';
  }
}
// The large CSS viewport paints real map pixels behind translucent browser bars.
// Never turn scrolling or the hidden part of that viewport into game padding.
const appHost = document.getElementById('app-host');
// Keep native selection menus off game controls; editing retains its normal menu.
const editableSelector = 'input, textarea, [contenteditable]:not([contenteditable="false"])';
function elementAt(node) {
  return node instanceof Element ? node : node?.parentElement;
}
function isEditable(node) {
  return !!elementAt(node)?.closest(editableSelector);
}
function clearGameSelection() {
  const selection = window.getSelection();
  if (!selection || selection.isCollapsed || !selection.rangeCount) return;
  // Safari can create a selection without a cancelable selectstart event.
  // Only remove ranges in the game, never a text field's editing selection.
  if (isEditable(selection.anchorNode) || isEditable(selection.focusNode)) return;
  for (let i = 0; i < selection.rangeCount; i++) {
    if (selection.getRangeAt(i).intersectsNode(appHost)) {
      selection.removeAllRanges();
      return;
    }
  }
}
document.addEventListener('selectionchange', clearGameSelection);
appHost.addEventListener('pointerdown', (event) => {
  if (!event.composedPath().some(isEditable)) clearGameSelection();
}, {capture: true, passive: true});
for (const type of ['selectstart', 'contextmenu']) {
  appHost.addEventListener(type, (event) => {
    if (!event.composedPath().some(isEditable)) {
      event.preventDefault();
      clearGameSelection();
    }
  }, {capture: true});
}
const safeAreaProbe = document.getElementById('safe-area-probe');
let topInset = 0;
let bottomInset = 0;
function updateBrowserViewport() {
  const viewport = window.visualViewport;
  // Portrait must fit above Safari's toolbar. Landscape keeps its large CSS
  // viewport for the map backdrop and native toolbar-collapse scrolling.
  if (!viewport || viewport.scale === undefined || viewport.scale === 1) {
    document.documentElement.style.setProperty(
      '--game-visible-height', `${viewport ? viewport.height : window.innerHeight}px`);
  }
  const safeArea = getComputedStyle(safeAreaProbe);
  const nextTop = Math.max(0, parseFloat(safeArea.paddingTop) || 0);
  const nextBottom = Math.max(0, parseFloat(safeArea.paddingBottom) || 0);
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

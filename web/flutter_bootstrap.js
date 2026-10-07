{{flutter_js}}
{{flutter_build_config}}
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?v={{flutter_service_worker_version}}';
  }
}
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
  return _flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
}
startCurrentBuild();

{{flutter_js}}
{{flutter_build_config}}
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += '?v=completed-town-outline-v1';
}
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});

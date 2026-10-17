import 'coastal_assets_native.dart'
    if (dart.library.js_interop) 'coastal_assets_web.dart'
    as platform;

/// Refresh coastline geometry and names together without retaining JSON strings.
Future<String> loadCoastalAsset(String key, {String version = '20261015-v1'}) =>
    platform.loadCoastalAsset(key, version: version);

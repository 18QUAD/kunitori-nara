import 'dart:convert';
import 'dart:ui_web' as ui_web;

Future<String> loadCoastalAsset(
  String key, {
  String version = '20261015-v1',
}) async {
  // The engine accepts a URL query. PlatformAssetBundle escapes '?' as a path
  // character, so passing this versioned key through rootBundle causes a 404.
  final data = await ui_web.assetManager.load('$key?coast=$version');
  return utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'prepared_map_assets.dart';
import 'package:kunitori/prepared_map_bytes.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  // Native map tests use the checked-in, verified packs without downloading.
  final cache = Directory.systemTemp.createTempSync('kunitori-map-tests-');
  Link(
    '${cache.path}/map-packs-v1',
  ).createSync(Directory('data/prepared_maps/map-packs').absolute.path);
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => cache.path,
  );
  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    message,
  ) async {
    final name = utf8.decode(
      message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
    if (name == 'data/prepared_maps/map-image-manifest.json') {
      final index = jsonDecode(File(name).readAsStringSync());
      index['packBaseUrl'] = 'https://example.test/';
      return Uint8List.fromList(
        utf8.encode(jsonEncode(index)),
      ).buffer.asByteData();
    }
    if (name.startsWith('assets/data/map_images/')) {
      return preparedMapBytes(name).buffer.asByteData();
    }
    final source = File(name);
    final path =
        source.existsSync() ? source : File('build/unit_test_assets/$name');
    return path.existsSync()
        ? path.readAsBytesSync().buffer.asByteData()
        : null;
  });
  // Process-wide futures must be created outside a widget test's fake clock.
  await PreparedMapBytes.shared.prepare();
  tearDownAll(() => cache.deleteSync(recursive: true));
  await main();
}

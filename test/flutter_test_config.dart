import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'prepared_map_assets.dart';
import 'package:kunitori/prepared_map_bytes.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    message,
  ) async {
    final name = utf8.decode(
      message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
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
  await main();
}

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/rendering_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bounds both framework images and the independent engine GPU cache',
    () async {
      MethodCall? received;
      const channel = MethodChannel('flutter/skia', JSONMethodCodec());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await configureRenderingMemory();
      expect(received!.method, 'Skia.setResourceCacheMaxBytes');
      expect(received!.arguments, 16 * 1024 * 1024);
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        16 * 1024 * 1024,
      );
      expect(PaintingBinding.instance.imageCache.maximumSize, 24);
    },
  );
}

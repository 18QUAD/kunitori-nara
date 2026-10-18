import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

const renderingCacheBytes = 16 * 1024 * 1024;

/// Engine/GPU caches are independent of the bounded map tile caches.
Future<void> configureRenderingMemory() async {
  PaintingBinding.instance.imageCache
    ..maximumSize = 24
    ..maximumSizeBytes = renderingCacheBytes;
  await const OptionalMethodChannel(
    'flutter/skia',
    JSONMethodCodec(),
  ).invokeMethod<void>('Skia.setResourceCacheMaxBytes', renderingCacheBytes);
}

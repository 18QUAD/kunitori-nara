import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// GSI elevation-derived hillshade, in the map's linear longitude/latitude grid.
class Relief {
  Relief(this.image, this.west, this.south, this.east, this.north);
  final ui.Image image;
  final double west, south, east, north;

  static Future<Relief> load() async {
    final metadata =
        jsonDecode(await rootBundle.loadString('assets/data/nara_relief.json'))
            as Map<String, dynamic>;
    final bytes = await rootBundle.load('assets/data/nara_relief.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      final frame = await codec.getNextFrame();
      return Relief(
        frame.image,
        (metadata['west'] as num).toDouble(),
        (metadata['south'] as num).toDouble(),
        (metadata['east'] as num).toDouble(),
        (metadata['north'] as num).toDouble(),
      );
    } finally {
      codec.dispose();
    }
  }
}

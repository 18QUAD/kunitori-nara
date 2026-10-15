import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// GSI elevation-derived hillshade, in the map's linear longitude/latitude grid.
class Relief {
  Relief(this.image, this.west, this.south, this.east, this.north);
  final ui.Image image;
  final double west, south, east, north;
  final List<Relief> additionalPatches = [];
  Iterable<Relief> get patches => [this, ...additionalPatches];

  void dispose() {
    for (final patch in patches) {
      patch.image.dispose();
    }
  }

  static Future<Map<String, dynamic>>? _index;

  static Future<Relief> loadPrefecture(String id) async {
    if (id == '29') return load();
    final index =
        await (_index ??= rootBundle
            .loadString('assets/data/relief/index.json')
            .then((value) => jsonDecode(value) as Map<String, dynamic>));
    final ids = (index['prefectures'][id] as List).cast<String>().toSet();
    final patches = <Relief>[];
    try {
      for (final row in index['tiles'] as List) {
        final key = "${row['x']}_${row['y']}";
        if (!ids.contains(key)) continue;
        patches.add(
          await _decode(
            row as Map<String, dynamic>,
            'assets/data/relief/$key.png',
          ),
        );
      }
      if (patches.isEmpty) throw const FormatException('起伏データがありません。');
      return patches.first..additionalPatches.addAll(patches.skip(1));
    } catch (_) {
      for (final patch in patches) {
        patch.image.dispose();
      }
      rethrow;
    }
  }

  static Future<Relief> loadNational() async {
    final metadata =
        jsonDecode(await rootBundle.loadString('assets/data/japan_relief.json'))
            as Map<String, dynamic>;
    return _decode(metadata, 'assets/data/japan_relief.png');
  }

  static Future<Relief> load() async {
    final metadata =
        jsonDecode(await rootBundle.loadString('assets/data/nara_relief.json'))
            as Map<String, dynamic>;
    return _decode(metadata, 'assets/data/nara_relief.png');
  }

  static Future<Relief> _decode(
    Map<String, dynamic> metadata,
    String path,
  ) async {
    final bytes = await rootBundle.load(path);
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

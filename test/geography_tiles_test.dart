import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/water.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pyramid covers 47 prefectures and matches physical display resolution',
    () {
      final json = jsonDecode(
        File('assets/data/map_tiles/index.json').readAsStringSync(),
      );
      final index = GeographyTileIndex.fromJson(json);
      expect((json['prefectureCoverage'] as Map).length, 47);
      expect(
        (json['prefectureCoverage'] as Map).values.every((n) => n > 0),
        isTrue,
      );
      expect(index.levelFor(20), 0);
      expect(index.levelFor(65), 1);
      expect(index.levelFor(1000), 4);
      expect(index.levelFor(60000), 4);
    },
  );

  test(
    'real raster water preserves Lake Biwa and its island at multiple scales',
    () async {
      Future<List<int>> pixel(double lon, double lat, int level) async {
        final span = GeographyTileIndex.span(level);
        final x = ((lon - 120) / span).floor();
        final y = ((48 - lat) / span).floor();
        final bytes =
            File(
              'assets/data/map_tiles/${level}_${x}_${y}_detail.png',
            ).readAsBytesSync();
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        final rgba =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final px = ((lon - 120 - x * span) / span * 256).floor();
        final py = ((48 - lat - y * span) / span * 256).floor();
        final start = (py * 256 + px) * 4;
        final result = [for (var c = 0; c < 4; c++) rgba.getUint8(start + c)];
        image.dispose();
        codec.dispose();
        return result;
      }

      for (final level in [2, 4]) {
        final water = await pixel(136.05, 35.25, level);
        expect(water.take(3), [0x79, 0xD9, 0xFF]);
        expect(water[3], 255);
      }
      final island = await pixel(136.143, 35.4219, 4);
      expect(island, isNot([0x79, 0xD9, 0xFF, 255]));
      // Building land at Tokyo's metropolitan government office remains lavender.
      final urban = await pixel(139.6917, 35.6896, 4);
      expect(urban[0], greaterThan(urban[1]));
      expect(urban[2], greaterThan(urban[0]));
    },
  );

  test(
    'every runtime water label asset loads without full vector geometry',
    () async {
      Offset project(math.Point<double> p) => Offset(p.x, p.y);
      for (final id in [
        'national',
        for (var i = 1; i <= 47; i++) '$i'.padLeft(2, '0'),
      ]) {
        final water = await WaterLayer.loadLabels(
          project,
          national: id == 'national',
          prefectureId: id,
        );
        expect(water.rivers.getBounds(), Rect.zero);
        expect(water.areas.getBounds(), Rect.zero);
        if (id == 'national' || id == '25') {
          expect(water.labels.map((l) => l.name), contains('琵琶湖'));
        }
      }
    },
  );

  test(
    'decoded image cache deduplicates requests and bounds unpinned memory',
    () async {
      final index = await GeographyTileIndex.load();
      final keys =
          index.available.where((k) => k.endsWith('_shade')).take(3).toList();
      final cache = GeographyImageCache(capacity: 2);
      final owner = Object();
      cache.pin(owner, {keys.first});
      final pair = await Future.wait([
        cache.load(keys.first),
        cache.load(keys.first),
      ]);
      expect(identical(pair[0], pair[1]), isTrue);
      await cache.load(keys[1]);
      await cache.load(keys[2]);
      cache.pin(owner, {keys.first});
      expect(cache.length, 2);
      expect(cache.peek(keys.first), same(pair.first));
      cache.release(owner);
      expect(cache.length, lessThanOrEqualTo(2));
    },
  );
}

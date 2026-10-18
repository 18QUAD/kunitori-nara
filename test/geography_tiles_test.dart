import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:kunitori/water_mesh.dart';
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
        File('assets/data/map_tiles_uniform/index-dry.json').readAsStringSync(),
      );
      final index = GeographyTileIndex.fromJson(json);
      expect((json['prefectureCoverage'] as Map).length, 47);
      expect(
        (json['prefectureCoverage'] as Map).values.every((n) => n > 0),
        isTrue,
      );
      expect(index.layerLevel(6, 'shade'), 5);
      expect(index.layerLevel(6, 'detail'), 6);
      expect(index.layerLevel(3, 'shade'), 3);
      // A mountain-only fine cell still uses its terrain parent.
      final shadeKey = index.available.firstWhere(
        (key) => key.startsWith('5_') && key.endsWith('_shade'),
      );
      final pieces = shadeKey.split('_');
      expect(
        index.hasTile(
          6,
          int.parse(pieces[1]) * 2,
          int.parse(pieces[2]) * 2,
          'shade',
        ),
        isTrue,
      );
      expect(index.levelFor(20), 0);
      expect(index.levelFor(65), 1);
      expect(index.levelFor(1000), 4);
      expect(index.levelFor(60000), 4);
      for (var i = 1; i <= 47; i++) {
        final id = '$i'.padLeft(2, '0');
        expect(index.levelFor(2000, prefectureId: id), 5);
        expect(index.levelFor(60000, prefectureId: id), 6);
      }
    },
  );

  test(
    'cached precise water preserves Lake Biwa, islands and overview filtering',
    () async {
      Future<List<int>> pixel(
        double lon,
        double lat,
        int level, {
        String layer = 'detail',
      }) async {
        final ppd = 4096.0 * math.pow(2, level);
        final id =
            layer == 'overview'
                ? 'national'
                : lon < 136
                ? '29'
                : '25';
        final mesh = WaterMesh(
          ByteData.sublistView(
            File('assets/data/water_mesh/$id.bin').readAsBytesSync(),
          ),
          (math.Point<double> p) =>
              Offset(.5 + (p.x - lon) * ppd, .5 + (lat - p.y) * ppd),
        );
        final recorder = ui.PictureRecorder();
        mesh.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 1, 1), 1);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1, 1);
        final rgba =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final result = [for (var c = 0; c < 4; c++) rgba.getUint8(c)];
        image.dispose();
        picture.dispose();
        return result;
      }

      for (final level in [2, 4]) {
        final water = await pixel(136.05, 35.25, level);
        expect(water.take(3), [0x79, 0xD9, 0xFF]);
        expect(water[3], 255);
      }
      for (final level in [2, 4]) {
        expect(await pixel(136.05, 35.25, level, layer: 'overview'), [
          0x79,
          0xD9,
          0xFF,
          255,
        ]);
      }
      final island = await pixel(136.143, 35.4219, 4);
      expect(island, isNot([0x79, 0xD9, 0xFF, 255]));
      final pond = await pixel(135.72145, 34.7427935, 4);
      final overviewPond = await pixel(
        135.72145,
        34.7427935,
        4,
        layer: 'overview',
      );
      expect(pond[1], greaterThan(pond[0] + 25));
      expect(overviewPond[3], 0);
      expect(
        await pixel(136.143, 35.4219, 4, layer: 'overview'),
        isNot([0x79, 0xD9, 0xFF, 255]),
      );
      // Building land at Tokyo's metropolitan government office remains lavender.
      const span = 0.25;
      final x = ((139.6917 - 120) / span).floor(),
          y = ((48 - 35.6896) / span).floor();
      final codec = await ui.instantiateImageCodec(
        File(
          'assets/data/map_tiles_uniform/dry_4_${x}_${y}_detail.webp',
        ).readAsBytesSync(),
      );
      final urbanImage = (await codec.getNextFrame()).image;
      final pixels =
          (await urbanImage.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = ((139.6917 - 120 - x * span) / span * 256).floor(),
          py = ((48 - 35.6896 - y * span) / span * 256).floor();
      final urban = [
        for (var c = 0; c < 4; c++) pixels.getUint8((py * 256 + px) * 4 + c),
      ];
      urbanImage.dispose();
      codec.dispose();
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
      cache.clearUnused();
      expect(cache.length, 1);
      expect(cache.peek(keys.first), same(pair.first));
      cache.release(owner);
      cache.clearUnused();
      expect(cache.length, 0);
    },
  );
  testWidgets('background raster surface stays viewport-sized at deep zoom', (
    tester,
  ) async {
    final transform =
        TransformationController()..value = (Matrix4.identity()..scale(50.0));
    await tester.pumpWidget(
      MaterialApp(
        home: OverflowBox(
          maxWidth: 1440,
          maxHeight: 1360,
          child: SizedBox(
            width: 1440,
            height: 1360,
            child: GeographyTiles(
              transform: transform,
              project: (p) => Offset((p.x - 120) * 64, (48 - p.y) * 64),
              viewport: const Size(390, 400),
              clip: Path()..addRect(const Rect.fromLTWH(0, 0, 1440, 1360)),
              enabled: true,
            ),
          ),
        ),
      ),
    );
    Size rasterSize() => tester.getSize(
      find
          .descendant(
            of: find.byType(GeographyTiles),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    for (final zoom in [50.0, 150.0]) {
      transform.value = Matrix4.identity()..scale(zoom);
      await tester.pump(const Duration(milliseconds: 100));
      expect(rasterSize().width * zoom, closeTo(390, 0.01));
      expect(rasterSize().height * zoom, closeTo(400, 0.01));
    }
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });
}

import 'prepared_map_assets.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/map_image_budget.dart';
import 'package:kunitori/water.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'finished water backgrounds retain lakes, islands and overview filtering',
    () async {
      Future<List<int>> pixel(
        double lon,
        double lat,
        int level, {
        String layer = 'background',
      }) async {
        final span = GeographyTileIndex.span(level);
        final x = ((lon - 120) / span).floor(), y = ((48 - lat) / span).floor();
        final codec = await ui.instantiateImageCodec(
          preparedMapBytes(
            'assets/data/map_images/${level}_${x}_${y}_$layer.webp',
          ),
        );
        final image = (await codec.getNextFrame()).image;
        final bytes =
            (await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba,
            ))!;
        final px = ((lon - 120 - x * span) / span * 512).floor(),
            py = ((48 - lat - y * span) / span * 512).floor();
        final result = [
          for (var c = 0; c < 4; c++) bytes.getUint8((py * 512 + px) * 4 + c),
        ];
        image.dispose();
        codec.dispose();
        return result;
      }

      bool blue(List<int> p) =>
          p[2] > 210 && p[1] > 180 && p[0] < 160 && p[3] > 240;
      for (final level in [5, 8]) {
        expect(blue(await pixel(136.05, 35.25, level)), isTrue);
      }
      expect(blue(await pixel(136.05, 35.25, 5, layer: 'overview')), isTrue);
      expect(blue(await pixel(136.143, 35.4219, 8)), isFalse);
      expect(blue(await pixel(135.72145, 34.7427935, 8)), isTrue);
      expect(
        blue(await pixel(135.72145, 34.7427935, 5, layer: 'overview')),
        isFalse,
      );
      // A Tokyo urban cell away from the water overlay.
      final urban = await pixel(139.7421875, 35.703125, 5);
      expect(urban[2], greaterThan(urban[0]));
      expect(urban[0], greaterThan(urban[1]));
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
          index.available
              .where((k) => k.endsWith('_background'))
              .take(3)
              .toList();
      final beforeBytes = MapImageBudget.shared.retainedBytes;
      final cache = GeographyImageCache(capacity: 2);
      final owner = Object();
      cache.pin(owner, {keys.first});
      final pair = await Future.wait([
        cache.load(keys.first),
        cache.load(keys.first),
      ]);
      expect(identical(pair[0], pair[1]), isTrue);
      final imageBytes = pair.first.width * pair.first.height * 4;
      expect(MapImageBudget.shared.retainedBytes - beforeBytes, imageBytes);
      await cache.load(keys[1]);
      await cache.load(keys[2]);
      cache.pin(owner, {keys.first});
      expect(cache.length, 2);
      expect(MapImageBudget.shared.retainedBytes - beforeBytes, imageBytes * 2);
      expect(cache.peek(keys.first), same(pair.first));
      cache.clearUnused();
      expect(cache.length, 1);
      expect(cache.peek(keys.first), same(pair.first));
      cache.release(owner);
      cache.clearUnused();
      expect(cache.length, 0);
      expect(MapImageBudget.shared.retainedBytes, beforeBytes);
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

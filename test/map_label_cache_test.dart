import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/map_label.dart';
import 'package:kunitori/national_atlas.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native label ownership is bounded and reuses repeated text', () {
    final cache = MapLabelCache(capacity: 16);
    final first = cache.obtain('池之内', 2.0);
    for (var i = 0; i < 2000; i++) {
      expect(identical(cache.obtain('池之内', 2.0), first), isTrue);
    }
    expect(cache.created, 1);
    for (var i = 0; i < 200; i++) {
      cache.obtain('町$i', 4.0);
    }
    expect(cache.length, 16);
    // A visible set just over capacity must retain the existing hot labels.
    final names = [for (var i = 0; i < 17; i++) 'visible$i'];
    for (var frame = 0; frame < 10; frame++) {
      cache.beginFrame(names, 2);
      for (final name in names) {
        cache.release(cache.obtain(name, 2));
      }
    }
    expect(cache.created, lessThan(250));
    cache.dispose();
    expect(cache.length, 0);
  });

  testWidgets(
    'Nara city pans bound offscreen layout and reuse native paragraphs',
    (tester) async {
      final data = await tester.runAsync(NationalAtlas.load);
      await tester.runAsync(() => data!.ensureGeometry('29'));
      final atlas = data!.atlas;
      final town = atlas.towns.values.firstWhere((t) => t.cityId == '29201');
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 375,
            height: 500,
            child: TerritoryMap(
              atlas: atlas,
              game: Game(atlas),
              selected: town.id,
              cityId: '29201',
              focusVersion: 0,
              onSelected: (_) {},
              onCitySelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      dynamic painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .firstWhere((p) {
            if (p.runtimeType.toString() != '_MapPainter') return false;
            return (p as dynamic).foreground as bool;
          });
      final dynamic current = painter();
      final Rect box = current.bounds[town.id];
      final controller = viewer.transformationController!;
      controller.value =
          Matrix4.identity()
            ..translate(180 - box.center.dx * 5.32, 240 - box.center.dy * 5.32)
            ..scale(5.32);
      await tester.pump();
      final MapLabelCache cache = painter().labelCache;
      final before = cache.created;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // Repeated foreground paints at the same view formerly laid out every town.
      for (var i = 0; i < 100; i++) {
        painter().paint(canvas, const Size(1100, 1500));
      }
      expect(cache.created - before, lessThan(2000));
      expect(cache.length, lessThanOrEqualTo(128));
      expect(cache.length, lessThan(atlas.byCity['29201']!.length ~/ 2));
      recorder.endRecording().dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(cache.length, 0);
    },
  );
}

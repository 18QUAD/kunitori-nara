import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/geography_tiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GeographyTileIndex.load());
  testWidgets('Nabari combined backgrounds stay sharp and reuse images', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    final transform =
        TransformationController()..value = (Matrix4.identity()..scale(14.0));
    final clip = Path()..addRect(const Rect.fromLTWH(0, 0, 1100, 1500));
    Offset project(math.Point<double> p) =>
        Offset((p.x - 136.12) * 600, (34.63 - p.y) * 600);
    Widget map() => MaterialApp(
      home: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: 1100,
        maxHeight: 1500,
        child: SizedBox(
          width: 1100,
          height: 1500,
          child: GeographyTiles(
            enabled: true,
            transform: transform,
            project: project,
            viewport: const Size(375, 450),
            clip: clip,
            prefectureId: '24',
          ),
        ),
      ),
    );
    List<dynamic> tiles() {
      final dynamic painter =
          tester
              .widget<CustomPaint>(
                find
                    .descendant(
                      of: find.byType(GeographyTiles),
                      matching: find.byType(CustomPaint),
                    )
                    .first,
              )
              .painter;
      return (painter.tiles as Iterable).toList();
    }

    try {
      await tester.pumpWidget(map());
      final ready = find.bySemanticsLabel('背景地図の読込完了');
      for (final zoom in [14.0, 48.0, 150.0, 8.0]) {
        transform.value = Matrix4.identity()..scale(zoom);
        for (var frame = 0; frame < 150; frame++) {
          await tester.pump();
          for (final tile in tiles()) {
            expect(
              tile.image.width / (tile.rect.width * zoom),
              greaterThanOrEqualTo(2),
              reason:
                  'No enlarged coarse water image, even on the first zoom frame',
            );
          }
          if (ready.evaluate().isNotEmpty) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(ready, findsOneWidget);
        expect(tiles(), isNotEmpty);
        expect(tiles().length, lessThanOrEqualTo(12));
        expect(
          tiles().every((tile) => tile.layer == 'background'),
          isTrue,
          reason:
              'Terrain, urban land and water must be displayed in the same background image',
        );
        expect(
          find.descendant(
            of: find.byType(GeographyTiles),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      }
      final before = tiles().map((tile) => tile.image).toList();
      await tester.pumpWidget(map());
      expect(
        tiles().map((tile) => tile.image).toList(),
        before,
        reason: 'A game tap must not rebuild water images',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      semantics.dispose();
      transform.dispose();
    }
  });
}

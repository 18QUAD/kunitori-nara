import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/border_tiles.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/map_paint_snapshot.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The process-wide manifest future must belong to the real async zone,
  // rather than the fake clock of whichever widget test happens to run first.
  setUpAll(() => GeographyTileIndex.loadBorders());

  Atlas nara() => Atlas.fromJson(
    jsonDecode(File('assets/data/nara.json').readAsStringSync()),
  );

  test('immutable map state changes only when displayed colors change', () {
    final atlas = nara();
    final home = atlas.towns.values.firstWhere(
      (town) => town.neighbors.any((id) => atlas.towns[id]!.population >= 100),
    );
    final target = home.neighbors.firstWhere(
      (id) => atlas.towns[id]!.population >= 100,
    );
    final game =
        Game(atlas)
          ..setHome(home.id)
          ..selectAttackTarget(target);
    final before = MapPaintSnapshot(game);
    game.tap(target, DateTime.now());
    final oneTap = MapPaintSnapshot(game);
    expect(oneTap.sameColors(before), isTrue);
    expect(oneTap.sameForeground(before), isTrue);
    game.progress[target] = (atlas.towns[target]!.population / 10).ceil();
    final nextBand = MapPaintSnapshot(game);
    expect(nextBand.sameColors(oneTap), isFalse);
    expect(nextBand.sameForeground(oneTap), isTrue);
    game.progress[target] = atlas.towns[target]!.population - 1;
    game.tap(target, DateTime.now());
    final won = MapPaintSnapshot(game);
    expect(won.sameColors(nextBand), isFalse);
    expect(won.sameForeground(nextBand), isFalse);
  });

  test('baked boundaries cover every prefecture and all three map scopes', () {
    final data =
        jsonDecode(
              File('assets/data/border_tiles/index.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final index = GeographyTileIndex.fromJson(data);
    expect(index.minLevel, -3);
    expect(index.basePixelsPerDegree * (1 << index.maxLevel), 8192);
    expect((data['prefectureCoverage'] as Map).length, 47);
    for (final layer in ['pref', 'city', 'town']) {
      expect(index.available.any((key) => key.endsWith('_$layer')), isTrue);
      expect(index.layerLevel(6, layer), layer == 'town' ? 6 : 5);
    }
    for (final coverage in (data['prefectureCoverage'] as Map).values) {
      expect(coverage['townGroups'], greaterThan(0));
      for (final layer in ['pref', 'city', 'town']) {
        expect(coverage['6_$layer'], greaterThan(0));
      }
      expect(coverage['7_town'], greaterThan(0));
    }
    expect(index.levelFor(5), -3);
    expect(index.levelFor(20), -2);
    expect(index.levelFor(60000, prefectureId: '29'), 6);
  });

  testWidgets(
    'phone boundaries keep physical resolution without offscreen tiles',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(750, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      final transform =
          TransformationController()
            ..value =
                (Matrix4.identity()
                  ..translate(-196.5, -159.0)
                  ..scale(2.0));
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: 1100,
              maxHeight: 1500,
              child: SizedBox(
                width: 1100,
                height: 1500,
                child: BorderTiles(
                  transform: transform,
                  project:
                      (math.Point<double> p) =>
                          Offset((p.x - 134) * 128, (36 - p.y) * 128),
                  viewport: const Size(375, 450),
                  clip: Path()..addRect(const Rect.fromLTWH(0, 0, 1100, 1500)),
                  prefectureId: '29',
                  layer: 'town',
                ),
              ),
            ),
          ),
        );
        final ready = find.bySemanticsLabel('境界線画像の読込完了');
        for (var i = 0; i < 150 && ready.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        expect(ready, findsOneWidget);
        expect(tester.getRect(ready).width, lessThanOrEqualTo(1));
        expect(tester.getRect(ready).height, lessThanOrEqualTo(1));
        final dynamic painter =
            tester
                .widget<CustomPaint>(
                  find
                      .descendant(
                        of: find.byType(BorderTiles),
                        matching: find.byType(CustomPaint),
                      )
                      .first,
                )
                .painter;
        final tiles = (painter.tiles as Iterable).toList();
        expect(
          tiles.length,
          greaterThan(6),
          reason: 'Native phone pixels must not be downgraded to fit six tiles',
        );
        expect(tiles.length, lessThanOrEqualTo(24));
        for (final dynamic tile in tiles) {
          expect(
            tile.image.width / (tile.rect.width * 2),
            greaterThanOrEqualTo(2),
            reason:
                'Every loaded boundary image must match the physical pixels',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
        transform.dispose();
      }
    },
  );

  testWidgets('tap reuses boundary images and skips unchanged map paints', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final ready = find.bySemanticsLabel('境界線画像の読込完了');
      final atlas = nara();
      final home = atlas.towns.values.firstWhere(
        (town) =>
            town.neighbors.any((id) => atlas.towns[id]!.population >= 100),
      );
      final target = home.neighbors.firstWhere(
        (id) => atlas.towns[id]!.population >= 100,
      );
      final game =
          Game(atlas)
            ..setHome(home.id)
            ..selectAttackTarget(target);
      Widget screen() => MaterialApp(
        home: TerritoryMap(
          atlas: atlas,
          game: game,
          selected: target,
          cityId: home.cityId,
          focusVersion: 0,
          onSelected: (_) {},
          onCitySelected: (_) {},
        ),
      );
      await tester.pumpWidget(screen());
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        if (ready.evaluate().isNotEmpty &&
            find.text('山名を読み込み中…').evaluate().isEmpty &&
            find.text('川・湖を読み込み中…').evaluate().isEmpty) {
          break;
        }
      }
      expect(
        ready,
        findsOneWidget,
        reason: tester
            .widgetList<Semantics>(
              find.descendant(
                of: find.byType(BorderTiles),
                matching: find.byType(Semantics),
              ),
            )
            .map((widget) => widget.properties.label)
            .join(', '),
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final mapStack =
          (((viewer.child as GestureDetector).child as SizedBox).child
              as Stack);
      expect(mapStack.children.last, isA<BorderTiles>());
      dynamic mapPainter(bool foreground) {
        final current = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final box = (current.child as GestureDetector).child as SizedBox;
        final stack = box.child as Stack;
        final overlays = stack.children.whereType<RepaintBoundary>();
        final boundary = foreground ? overlays.last : overlays.first;
        return (boundary.child as CustomPaint).painter;
      }

      dynamic borderPainter() =>
          tester
              .widget<CustomPaint>(
                find
                    .descendant(
                      of: find.byType(BorderTiles),
                      matching: find.byType(CustomPaint),
                    )
                    .first,
              )
              .painter;
      final oldBorder = borderPainter();
      final oldBase = mapPainter(false);
      final oldForeground = mapPainter(true);
      final camera = viewer.transformationController!.value.clone();
      game.tap(target, DateTime.now());
      await tester.pumpWidget(screen());
      await tester.pump();
      expect(borderPainter().shouldRepaint(oldBorder), isFalse);
      expect(mapPainter(false).shouldRepaint(oldBase), isFalse);
      expect(mapPainter(true).shouldRepaint(oldForeground), isFalse);
      expect(viewer.transformationController!.value, camera);
      expect(game.progress[target], 1);
      // Borders remain present when the terrain layer is hidden.
      await tester.tap(find.byTooltip('起伏・市街地・山名・川・池・湖を非表示'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BorderTiles>(find.byType(BorderTiles)).enabled,
        isTrue,
      );
      expect(
        tester.widget<GeographyTiles>(find.byType(GeographyTiles)).enabled,
        isFalse,
      );
      expect(
        tester.widget<BorderTiles>(find.byType(BorderTiles)).boundaryLayer,
        'town',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      semantics.dispose();
    }
  });
}

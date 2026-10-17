import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/border_tiles.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/map_paint_snapshot.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(index.basePixelsPerDegree * (1 << index.maxLevel), 4096);
    expect((data['prefectureCoverage'] as Map).length, 47);
    for (final layer in ['pref', 'city', 'town']) {
      expect(index.available.any((key) => key.endsWith('_$layer')), isTrue);
      expect(index.layerLevel(6, layer), 5);
    }
    for (final coverage in (data['prefectureCoverage'] as Map).values) {
      expect(coverage['townGroups'], greaterThan(0));
      for (final layer in ['pref', 'city', 'town']) {
        expect(coverage['6_$layer'], greaterThan(0));
      }
    }
    expect(index.levelFor(5), -3);
    expect(index.levelFor(20), -2);
    expect(index.levelFor(60000, prefectureId: '29'), 5);
  });

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
      dynamic mapPainter(bool foreground) {
        final current = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final box = (current.child as GestureDetector).child as SizedBox;
        final stack = box.child as Stack;
        final boundary =
            (foreground ? stack.children.last : stack.children.first)
                as RepaintBoundary;
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

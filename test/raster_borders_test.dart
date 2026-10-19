import 'prepared_map_assets.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:kunitori/border_tiles.dart';
import 'package:kunitori/territory_map.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/map_paint_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GeographyTileIndex.load());
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

  test('prepared layers cover all scopes and step exactly once per button', () {
    final data = jsonDecode(
      File('assets/data/map_images/index.json').readAsStringSync(),
    );
    final index = GeographyTileIndex.fromJson(data);
    for (final layer in ['background', 'overview', 'pref', 'city', 'town']) {
      for (
        var level = index.minLevel;
        level <= index.layerMaxLevels[layer]!;
        level++
      ) {
        expect(
          index.available.any(
            (key) => key.startsWith('${level}_') && key.endsWith('_$layer'),
          ),
          isTrue,
        );
      }
    }
    for (final projection in [50.0, 600.0, 1539.689]) {
      for (var level = -3; level < 8; level++) {
        final scale = MapImageScale.scale(level, projection);
        expect(
          MapImageScale.snap(scale * 2, projection, 8),
          closeTo(MapImageScale.scale(level + 1, projection), 1e-8),
        );
        expect(MapImageScale.level(scale, projection), level);
      }
    }
  });
  test(
    'shared Osaka-Nara boundary remains a single thin white stroke',
    () async {
      final codec = await ui.instantiateImageCodec(
        preparedMapBytes('assets/data/map_images/5_125_108_pref.webp'),
      );
      final image = (await codec.getNextFrame()).image;
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
      for (var y = 120; y <= 124; y++) {
        var runs = 0, previous = false, coverage = 0.0;
        for (var x = 180; x <= 310; x++) {
          final offset = (y * 512 + x) * 4;
          final alpha = pixels.getUint8(offset + 3);
          final active = alpha >= 64;
          if (active && !previous) runs++;
          previous = active;
          coverage += alpha / 255;
          if (alpha > 0) {
            expect(
              [for (var c = 0; c < 3; c++) pixels.getUint8(offset + c)],
              [255, 255, 255],
            );
          }
        }
        expect(runs, 1);
        expect(coverage, lessThan(2.5));
      }
      image.dispose();
      codec.dispose();
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
        home: RepaintBoundary(
          key: const Key('whole-map'),
          child: TerritoryMap(
            atlas: atlas,
            game: game,
            selected: target,
            cityId: home.cityId,
            focusVersion: 0,
            onSelected: (_) {},
            onCitySelected: (_) {},
          ),
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
      final wholeMap = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('whole-map')),
      );
      final visibleRed = await tester.runAsync(() async {
        final image = await wholeMap.toImage(pixelRatio: 1);
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        var count = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) > 220 &&
              data.getUint8(i + 1) < 110 &&
              data.getUint8(i + 2) < 100) {
            count++;
          }
        }
        image.dispose();
        return count;
      });
      expect(
        visibleRed,
        greaterThan(20),
        reason: 'The attack outline must remain above the boundary images',
      );
      final mapStack =
          (((viewer.child as GestureDetector).child as SizedBox).child
              as Stack);
      expect(mapStack.children[3], isA<BorderTiles>());
      expect(mapStack.children[2], isA<RepaintBoundary>());
      expect(mapStack.children.last, isA<RepaintBoundary>());
      final dynamic colors = (mapStack.children[2] as RepaintBoundary).child;
      expect(colors.painter.colors, isTrue);
      dynamic mapPainter(bool foreground) {
        final current = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final box = (current.child as GestureDetector).child as SizedBox;
        final stack = box.child as Stack;
        final overlays = stack.children.whereType<RepaintBoundary>();
        final boundary = foreground ? overlays.last : overlays.elementAt(1);
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
      dynamic staticBase() {
        final current = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final box = (current.child as GestureDetector).child as SizedBox;
        return (((box.child as Stack).children.first as RepaintBoundary).child
                as CustomPaint)
            .painter;
      }

      final beforeConquestBase = staticBase();
      final beforeConquestColors = mapPainter(false);
      final beforeConquestForeground = mapPainter(true);
      final beforeConquestBorder = borderPainter();
      game.progress[target] = game.requiredTaps(atlas.towns[target]!) - 1;
      expect(game.tap(target, DateTime.now()), isTrue);
      await tester.pumpWidget(screen());
      await tester.pump();
      expect(
        staticBase().shouldRepaint(beforeConquestBase),
        isFalse,
        reason: 'Acquiring a town must not repaint unchanged land geometry',
      );
      expect(mapPainter(false).shouldRepaint(beforeConquestColors), isTrue);
      expect(mapPainter(true).shouldRepaint(beforeConquestForeground), isTrue);
      expect(borderPainter().shouldRepaint(beforeConquestBorder), isFalse);
      expect(viewer.transformationController!.value, camera);
      // Terrain cannot be toggled until both image workers finish.
      IconButton terrain() => tester
          .widgetList<IconButton>(find.byType(IconButton))
          .firstWhere((button) => button.tooltip == '起伏・市街地・山名・川・池・湖を非表示');
      for (var i = 0; i < 200 && terrain().onPressed == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        terrain().onPressed,
        isNotNull,
        reason: tester
            .stateList(find.byType(GeographyTiles))
            .map(
              (dynamic state) =>
                  '${state.statusLabel}; loading=${state.loading}; cache=${state.cache.length}',
            )
            .join(', '),
      );
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

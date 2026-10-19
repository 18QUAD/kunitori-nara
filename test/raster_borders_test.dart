import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  setUpAll(() async {
    await GeographyTileIndex.loadBorders();
    await GeographyTileIndex.load();
  });

  Atlas nara() => Atlas.fromJson(
    jsonDecode(File('assets/data/nara.json').readAsStringSync()),
  );

  testWidgets('zoom stays locked through queued work and image retirement', (
    tester,
  ) async {
    final events = <bool>[];
    final transform = TransformationController();
    final clip = Path()..addRect(const Rect.fromLTWH(0, 0, 800, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: BorderTiles(
          transform: transform,
          project: (p) => Offset(p.x, p.y),
          viewport: const Size(300, 300),
          clip: clip,
          layer: 'town',
          boundaryPaths: [
            Path()
              ..moveTo(100, 0)
              ..lineTo(100, 600),
          ],
          onBusyChanged: events.add,
        ),
      ),
    );
    for (var i = 0; i < 50 && events.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    // Start rasterization, then issue many changes before it can finish.
    for (var i = 0; i < 30; i++) {
      transform.value = Matrix4.identity()..scale(1.0 + i / 10);
    }
    expect(events, [true]);
    for (var i = 0; i < 150 && !events.contains(false); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(events, [
      true,
      false,
    ], reason: 'No unlock between stale and latest work');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });

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
              File(
                'assets/data/border_tiles/index-slim.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final index = GeographyTileIndex.fromJson(data);
    expect(index.minLevel, -3);
    expect(index.basePixelsPerDegree * (1 << index.maxLevel), 8192);
    expect((data['prefectureCoverage'] as Map).length, 47);
    expect(data['filenamePrefix'], GeographyImageCache.borders.filenamePrefix);
    expect(
      GeographyImageCache.borders.prefixFor('3_31_26_pref'),
      'slimshared_',
    );
    expect(GeographyImageCache.borders.prefixFor('6_31_26_town'), 'slim_');
    expect((data['sharedPrefectureMesh']['sourceSha256'] as Map).length, 47);
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

  test(
    'real prefecture border image has thin white lines without any casing',
    () async {
      final bytes =
          File(
            'assets/data/border_tiles/slimshared_3_31_26_pref.webp',
          ).readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
      var white = 0, nonWhite = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        if (pixels.getUint8(i + 3) == 0) continue;
        if (pixels.getUint8(i) == 255 &&
            pixels.getUint8(i + 1) == 255 &&
            pixels.getUint8(i + 2) == 255) {
          white++;
        } else {
          nonWhite++;
        }
      }
      expect(white, greaterThan(100));
      expect(nonWhite, 0);
      expect(image.width, 512);
      image.dispose();
      codec.dispose();
    },
  );

  test(
    'real Osaka–Nara shared border is one stroke at the finest prefecture LOD',
    () async {
      // Before the mesh, these rows contained two separate parallel strokes.
      final codec = await ui.instantiateImageCodec(
        File(
          'assets/data/border_tiles/slimshared_5_125_108_pref.webp',
        ).readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var y = 120; y <= 124; y++) {
        var runs = 0, previous = false;
        for (var x = 180; x <= 310; x++) {
          final active = pixels.getUint8((y * 512 + x) * 4 + 3) >= 64;
          if (active && !previous) runs++;
          previous = active;
        }
        expect(
          runs,
          1,
          reason: 'Osaka–Nara row $y must contain one shared boundary',
        );
      }
      image.dispose();
      codec.dispose();
    },
  );

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
        for (final zoom in [8.0, 1.0, 4.0]) {
          transform.value = Matrix4.identity()..scale(zoom);
          // No real-async delay: this inspects the very first zoom frame too.
          for (var frame = 0; frame < 100; frame++) {
            await tester.pump();
            final dynamic current =
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
            for (final dynamic tile in current.tiles as Iterable) {
              expect(
                tile.image.width / (tile.rect.width * zoom),
                greaterThanOrEqualTo(2),
                reason:
                    'Zoom frame $frame must not stretch an older LOD or coarse fallback',
              );
            }
            if (ready.evaluate().isNotEmpty) break;
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
          }
          expect(ready, findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
        transform.dispose();
      }
    },
  );

  testWidgets('all town scales cache the same thin screen stroke', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    final transform =
        TransformationController()..value = (Matrix4.identity()..scale(24.0));
    final clip = Path()..addRect(const Rect.fromLTWH(0, 0, 1100, 1500));
    final outline =
        Path()
          ..moveTo(3, 0)
          ..lineTo(3, 1500);
    Offset project(math.Point<double> p) => Offset(p.x * 600, p.y * 600);
    Widget map() => MaterialApp(
      home: OverflowBox(
        alignment: Alignment.topLeft,
        maxWidth: 1100,
        maxHeight: 1500,
        child: SizedBox(
          width: 1100,
          height: 1500,
          child: BorderTiles(
            transform: transform,
            project: project,
            viewport: const Size(375, 450),
            clip: clip,
            layer: 'town',
            boundaryPaths: [outline],
          ),
        ),
      ),
    );
    List<dynamic> images() {
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
      return (painter.tiles as Iterable).toList();
    }

    final ready = find.bySemanticsLabel('境界線画像の読込完了');
    try {
      await tester.pumpWidget(map());
      for (final zoom in [0.125, 0.5, 1.0, 2.0, 8.0, 24.0, 48.0, 150.0, 24.0]) {
        transform.value =
            Matrix4.identity()
              ..translate(50 - 3 * zoom, 0.0)
              ..scale(zoom);
        for (var frame = 0; frame < 100; frame++) {
          await tester.pump();
          for (final tile in images()) {
            expect(
              tile.image.width / (tile.rect.width * zoom),
              greaterThanOrEqualTo(2),
              reason:
                  'Even the first deep-zoom frame must not enlarge a coarse image',
            );
          }
          if (ready.evaluate().isNotEmpty) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(ready, findsOneWidget);
        expect(images(), isNotEmpty);
        expect(images().length, lessThanOrEqualTo(24));
        final tile = images().firstWhere(
          (tile) =>
              tile.rect.left <= 3 && tile.rect.right > 3 && tile.rect.top == 0,
        );
        final raster = tile.image as ui.Image;
        final data = await tester.runAsync(
          () => raster.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
        );
        var coverage = 0;
        for (var x = 0; x < 512; x++) {
          coverage += data!.getUint8((100 * 512 + x) * 4 + 3);
        }
        final density = raster.width / tile.rect.width;
        expect(
          coverage / 255 * zoom / density,
          inInclusiveRange(0.55, 0.75),
          reason:
              'Visible white stroke must remain about 0.65 CSS pixels at zoom $zoom',
        );
      }
      // A rebuild such as a gameplay tap reuses native images unchanged.
      final before = images().map((tile) => tile.image).toList();
      await tester.pumpWidget(map());
      expect(images().map((tile) => tile.image).toList(), before);
      // Verify the actual rasterized white stroke, not just the image dimensions.
      final image = images().first.image as ui.Image;
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
      );
      var alpha = 0;
      for (var x = 0; x < 512; x++) {
        final i = (100 * 512 + x) * 4;
        alpha += bytes!.getUint8(i + 3);
        if (bytes.getUint8(i + 3) > 0) {
          expect(bytes.getUint8(i), 255);
          expect(bytes.getUint8(i + 1), 255);
          expect(bytes.getUint8(i + 2), 255);
        }
      }
      expect(alpha / 255, inInclusiveRange(1.0, 1.5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      semantics.dispose();
      transform.dispose();
    }
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

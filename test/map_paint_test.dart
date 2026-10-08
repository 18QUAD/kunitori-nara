import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  testWidgets('GSI layers load and toggle independently without moving map', (
    tester,
  ) async {
    final atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
    final game = Game(atlas);
    await tester.pumpWidget(
      MaterialApp(
        home: TerritoryMap(
          atlas: atlas,
          game: game,
          selected: null,
          cityId: null,
          focusVersion: 0,
          onSelected: (_) {},
          onCitySelected: (_) {},
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    dynamic painter() {
      final current = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final box = (current.child as GestureDetector).child as SizedBox;
      return (box.child as CustomPaint).painter;
    }

    final dynamic withRelief = painter();
    expect(withRelief.relief, isNotNull);
    expect(withRelief.water, isNotNull);
    final originalWater = withRelief.water;
    await tester.tap(find.byTooltip('川・湖を非表示'));
    await tester.pumpAndSettle();
    expect(painter().water, isNull);
    expect(painter().relief, same(withRelief.relief));
    await tester.tap(find.byTooltip('川・湖を表示'));
    await tester.pumpAndSettle();
    expect(painter().water, same(originalWater));
    final Rect terrainRect = withRelief.reliefBounds;
    for (final Rect box in (withRelief.bounds as Map<String, Rect>).values) {
      expect(terrainRect.contains(box.topLeft), isTrue);
      expect(terrainRect.contains(box.bottomRight), isTrue);
    }
    final originalTransform = Matrix4.copy(
      viewer.transformationController!.value,
    );
    await tester.tap(find.byTooltip('起伏を非表示'));
    await tester.pumpAndSettle();
    expect(painter().relief, isNull);
    expect(painter().water, same(originalWater));
    expect(viewer.transformationController!.value, originalTransform);
    await tester.tap(find.byTooltip('起伏を表示'));
    await tester.pumpAndSettle();
    expect(painter().relief, same(withRelief.relief));
    expect(game.owned, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selected outline remains white over later neighboring shapes', (
    tester,
  ) async {
    final atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
    final towns = atlas.byCity.values.first.take(2).toList();
    await tester.pumpWidget(
      MaterialApp(
        home: TerritoryMap(
          atlas: atlas,
          game: Game(atlas),
          selected: towns.first.id,
          cityId: towns.first.cityId,
          focusVersion: 0,
          onSelected: (_) {},
          onCitySelected: (_) {},
        ),
      ),
    );
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final detector = viewer.child as GestureDetector;
    final canvasWidget = detector.child as SizedBox;
    final dynamic painter = (canvasWidget.child as CustomPaint).painter;
    final paths = painter.paths as Map<String, Path>;
    final bounds = painter.bounds as Map<String, Rect>;
    paths.clear();
    bounds.clear();
    for (var i = 0; i < 2; i++) {
      final rect = Rect.fromLTWH(i * 100.0, 0, 100, 100);
      paths[towns[i].id] = Path()..addRect(rect);
      bounds[towns[i].id] = rect;
    }
    viewer.transformationController!.value = Matrix4.identity();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(200, 100));
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage(200, 100);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      // The second town shares this edge and is painted after the selected town.
      final pixel = (10 * 200 + 100) * 4;
      for (var channel = 0; channel < 3; channel++) {
        expect(bytes.getUint8(pixel + channel), greaterThanOrEqualTo(245));
      }
      image.dispose();
    });
    picture.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

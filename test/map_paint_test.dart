import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  setUp(() => rootBundle.clear());
  testWidgets('GSI layers load and toggle together without moving map', (
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
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      if (find.text('市街地を読み込み中…').evaluate().isEmpty &&
          find.text('起伏を読み込み中…').evaluate().isEmpty &&
          find.text('川・湖を読み込み中…').evaluate().isEmpty &&
          find.text('山名を読み込み中…').evaluate().isEmpty) {
        break;
      }
    }
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
    // Sakurai's merged census geometry contains many tiny internal gaps.
    // Display outlines must suppress them without changing fill/hit geometry.
    final city = atlas.cities.entries.firstWhere((e) => e.value == '桜井市').key;
    final Path fill = withRelief.paths[city];
    final Path outline = withRelief.outlines[city];
    expect(fill.computeMetrics().length, greaterThan(100));
    expect(outline.computeMetrics().length, 1);
    expect(outline.getBounds(), fill.getBounds());
    expect(withRelief.relief, isNotNull);
    expect(withRelief.water, isNotNull);
    expect(withRelief.urban, isNotNull);
    expect(withRelief.mountains, isNotNull);
    final originalWater = withRelief.water;
    final Rect terrainRect = withRelief.reliefBounds;
    for (final Rect box in (withRelief.bounds as Map<String, Rect>).values) {
      expect(terrainRect.contains(box.topLeft), isTrue);
      expect(terrainRect.contains(box.bottomRight), isTrue);
    }
    final originalTransform = Matrix4.copy(
      viewer.transformationController!.value,
    );
    await tester.tap(find.byTooltip('起伏・市街地・山名・川・池・湖を非表示'));
    await tester.pumpAndSettle();
    expect(painter().relief, isNull);
    expect(painter().water, isNull);
    expect(painter().urban, isNull);
    expect(painter().mountains, isNull);
    expect(viewer.transformationController!.value, originalTransform);
    await tester.tap(find.byTooltip('起伏・市街地・山名・川・池・湖を表示'));
    await tester.pumpAndSettle();
    expect(painter().relief, same(withRelief.relief));
    expect(painter().water, same(originalWater));
    expect(painter().urban, same(withRelief.urban));
    expect(painter().mountains, same(withRelief.mountains));
    expect(game.owned, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selection and campaign stay red above white neighboring borders', (
    tester,
  ) async {
    final atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
    final city = atlas.cities.entries.firstWhere((e) => e.value == '桜井市').key;
    final sakurai = atlas.byCity[city]!.firstWhere((t) => t.name == '桜井');
    final towns = [
      sakurai,
      ...atlas.byCity[city]!.where((t) => t.id != sakurai.id).take(2),
    ];
    final game = Game(atlas)..attackTarget = towns[1].id;
    await tester.pumpWidget(
      MaterialApp(
        home: TerritoryMap(
          atlas: atlas,
          game: game,
          selected: towns.first.id,
          cityId: towns.first.cityId,
          focusVersion: 0,
          onSelected: (_) {},
          onCitySelected: (_) {},
        ),
      ),
    );
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      if (find.text('市街地を読み込み中…').evaluate().isEmpty &&
          find.text('起伏を読み込み中…').evaluate().isEmpty &&
          find.text('川・湖を読み込み中…').evaluate().isEmpty &&
          find.text('山名を読み込み中…').evaluate().isEmpty) {
        break;
      }
    }
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final detector = viewer.child as GestureDetector;
    final canvasWidget = detector.child as SizedBox;
    final dynamic painter = (canvasWidget.child as CustomPaint).painter;
    final paths = painter.paths as Map<String, Path>;
    final outlines = painter.outlines as Map<String, Path>;
    final bounds = painter.bounds as Map<String, Rect>;
    // The selected town in the reported screenshot has internal gap contours.
    expect(paths[sakurai.id]!.computeMetrics().length, greaterThan(1));
    expect(outlines[sakurai.id]!.computeMetrics().length, 1);
    expect(outlines[sakurai.id]!.getBounds(), paths[sakurai.id]!.getBounds());
    expect(painter.urban, isNotNull);
    // Cover all synthetic towns with urban land to verify borders stay above it.
    (painter.urban.areas as Path)
      ..reset()
      ..addRect(const Rect.fromLTWH(0, 0, 300, 100));
    (painter.reliefClip as Path)
      ..reset()
      ..addRect(const Rect.fromLTWH(0, 0, 300, 100));
    paths.clear();
    outlines.clear();
    bounds.clear();
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(i * 100.0, 0, 100, 100);
      paths[towns[i].id] = Path()..addRect(rect);
      outlines[towns[i].id] = Path()..addRect(rect);
      bounds[towns[i].id] = rect;
    }
    viewer.transformationController!.value = Matrix4.identity();
    final recorder = ui.PictureRecorder();
    // Render at 4x so subpixel white borders have fully covered pixels.
    painter.paint(Canvas(recorder)..scale(4), const Size(300, 100));
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage(1200, 400);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      // Selection and campaign strokes survive shared white borders.
      for (final point in [const Offset(100, 10), const Offset(150, 99)]) {
        final pixel = (point.dy.toInt() * 4 * 1200 + point.dx.toInt() * 4) * 4;
        expect(bytes.getUint8(pixel), greaterThanOrEqualTo(245));
        expect(bytes.getUint8(pixel + 1), lessThan(90));
        expect(bytes.getUint8(pixel + 2), lessThan(90));
      }
      // A neutral town keeps its white boundary.
      final pixel = (40 * 1200 + 1199) * 4;
      for (var channel = 0; channel < 3; channel++) {
        expect(bytes.getUint8(pixel + channel), greaterThanOrEqualTo(245));
      }
      image.dispose();
    });
    picture.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

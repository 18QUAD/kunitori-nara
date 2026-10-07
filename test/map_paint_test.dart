import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/territory_map.dart';

void main() {
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

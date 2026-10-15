import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/urban.dart';

void main() {
  testWidgets(
    'real Tokyo building land is lavender and remains clipped in every view',
    (tester) async {
      Offset project(point) =>
          Offset((point.x - 139) * 800, (36 - point.y) * 1200);
      for (final national in [false, true]) {
        final urban = await tester.runAsync(
          () =>
              UrbanLayer.load(project, prefectureId: '13', national: national),
        );
        expect(urban, isNotNull);
        expect(urban!.rasters, isNotEmpty);
        // Tokyo Metropolitan Government Building, 139.6917E / 35.6896N,
        // falls inside a source building-land mesh, away from its pixel edge.
        Future<List<int>> pixel({required bool clipped}) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 800, 800),
            Paint()..color = const Color(0xFF43616A),
          );
          urban.paint(
            canvas,
            Path()..addRect(Rect.fromLTWH(0, 0, clipped ? 500 : 800, 800)),
          );
          final picture = recorder.endRecording();
          final result = await tester.runAsync(() async {
            final image = await picture.toImage(800, 800);
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            const start = (372 * 800 + 553) * 4;
            final result = [
              for (var c = 0; c < 4; c++) bytes.getUint8(start + c),
            ];
            image.dispose();
            return result;
          });
          picture.dispose();
          return result!;
        }

        final visible = await pixel(clipped: false);
        expect(visible[0], greaterThan(0x43));
        expect(visible[2], greaterThan(visible[0]));
        expect(visible[3], 255);
        expect(await pixel(clipped: true), [0x43, 0x61, 0x6a, 255]);
        urban.dispose();
      }
    },
  );
}

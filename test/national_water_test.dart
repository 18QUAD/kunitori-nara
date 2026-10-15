import 'support/source_assets.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/water.dart';

void main() {
  useSourceAssets();
  testWidgets(
    'Lake Biwa, its island and clipped blue water render in prefecture and national maps',
    (tester) async {
      Offset project(math.Point<double> p) =>
          Offset((p.x - 135.8) * 1000, (35.6 - p.y) * 1000);
      for (final mode in ['county', 'municipal', 'national']) {
        final national = mode == 'national';
        final water = await tester.runAsync(
          () =>
              WaterLayer.load(project, prefectureId: '25', national: national),
        );
        expect(water, isNotNull);
        expect(
          water!.areas.contains(project(const math.Point(136.05, 35.25))),
          isTrue,
        );
        expect(
          water.areas.contains(project(const math.Point(136.143, 35.4219))),
          isFalse,
        );
        expect(water.rivers.computeMetrics(), isNotEmpty);
        expect(water.labels.map((l) => l.name), contains('琵琶湖'));
        Future<List<int>> pixel({required bool clipped}) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 400, 600),
            Paint()..color = const Color(0xFF43616A),
          );
          water.paint(
            canvas,
            Path()..addRect(Rect.fromLTWH(0, 0, clipped ? 200 : 400, 600)),
            municipal: mode == 'municipal',
            viewport: const Rect.fromLTWH(0, 0, 400, 600),
          );
          final picture = recorder.endRecording();
          final result = await tester.runAsync(() async {
            final image = await picture.toImage(400, 600);
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            const start = (350 * 400 + 250) * 4;
            final result = [
              for (var c = 0; c < 4; c++) bytes.getUint8(start + c),
            ];
            image.dispose();
            return result;
          });
          picture.dispose();
          return result!;
        }

        expect(await pixel(clipped: false), [0x79, 0xd9, 0xff, 255]);
        expect(await pixel(clipped: true), [0x43, 0x61, 0x6a, 255]);
      }
    },
  );
}

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_boundary.dart';
import 'package:kunitori/office_symbols.dart';
import 'package:kunitori/prepared_territory.dart';

void main() {
  test('Mie mask excludes the inland overhang in the coarse outline', () async {
    final prepared = await PreparedTerritory.load('24');
    final mask = prepared.path('pref', (p) => Offset(p.x, p.y));
    // Outside both the detailed municipalities and MLIT N03 Mie boundaries.
    // The old coarse prefecture outline incorrectly included this location.
    expect(mask.contains(const Offset(136.05192309050943, 34.657852)), isFalse);
    expect(mask.contains(const Offset(136.13, 34.768)), isTrue);
  });

  testWidgets('dense Mie mask matches its geometry at northern inland zoom', (
    tester,
  ) async {
    final prepared = await PreparedTerritory.load('24');
    final rings = prepared.polygons('pref');
    final vertices = rings
        .expand((p) => p)
        .fold<int>(0, (n, r) => n + r.length);
    expect(vertices, greaterThan(65535));
    final mask = prepared.path(
      'pref',
      (p) => Offset((p.x - 136.0) * 1600, (35.15 - p.y) * 1600),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 640,
            height: 640,
            child: MapBoundaryScene(
              boundary: mask,
              children: const [
                Positioned.fill(child: ColoredBox(color: Colors.white)),
                SizedBox.expand(),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage();
      expect(image.width, 640);
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var inside = 0, outside = 0;
      for (var y = 8; y < image.height - 8; y += 32) {
        for (var x = 8; x < image.width - 8; x += 32) {
          final point = Offset(x + .5, y + .5);
          final expected = mask.contains(point);
          // Skip antialiased edge pixels; compare unequivocal land/outside.
          if ([
            const Offset(-2, -2),
            const Offset(2, -2),
            const Offset(-2, 2),
            const Offset(2, 2),
          ].any((d) => mask.contains(point + d) != expected)) {
            continue;
          }
          if (expected) {
            inside++;
          } else {
            outside++;
          }
          expect(
            pixels.getUint8((y * image.width + x) * 4 + 3),
            expected ? 255 : 0,
            reason: 'Dense northern Mie clip differs at scene point $point',
          );
        }
      }
      expect(inside, greaterThan(20));
      expect(outside, greaterThan(20));
      image.dispose();
    });
  });

  testWidgets('terrain is clipped while a coastal office symbol stays whole', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 120,
            height: 100,
            child: MapBoundaryScene(
              boundary: Path()..addRect(const Rect.fromLTWH(0, 0, 90, 100)),
              children: const [
                Positioned.fill(child: ColoredBox(color: Color(0xff123456))),
                Positioned.fill(child: CustomPaint(painter: _CoastalOffice())),
              ],
            ),
          ),
        ),
      ),
    );
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final recorder = ui.PictureRecorder();
      const _CoastalOffice().paint(Canvas(recorder), const Size(120, 100));
      final picture = recorder.endRecording();
      final reference = await picture.toImage(120, 100);
      final expected =
          (await reference.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      expect(bytes.getUint8((10 * 120 + 10) * 4 + 3), 255);
      expect(bytes.getUint8((80 * 120 + 110) * 4 + 3), 0);
      var symbolPixels = 0;
      for (var y = 40; y < 60; y++) {
        for (var x = 91; x < 100; x++) {
          final offset = (y * 120 + x) * 4;
          if (expected.getUint8(offset + 3) == 0) continue;
          symbolPixels++;
          for (var c = 0; c < 4; c++) {
            expect(
              bytes.getUint8(offset + c),
              expected.getUint8(offset + c),
              reason: 'Office symbol must remain intact outside the coastline',
            );
          }
        }
      }
      expect(symbolPixels, greaterThan(10));
      image.dispose();
      reference.dispose();
      picture.dispose();
    });
  });
}

class _CoastalOffice extends CustomPainter {
  const _CoastalOffice();
  @override
  void paint(Canvas canvas, Size size) =>
      paintOfficeSymbol(canvas, const Offset(88, 50), 1, isCity: true);
  @override
  bool shouldRepaint(_CoastalOffice old) => false;
}

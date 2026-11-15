import 'package:kunitori/bounded_map_clip.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_boundary.dart';
import 'package:kunitori/office_symbols.dart';
import 'package:kunitori/prepared_territory.dart';

void main() {

  test('cell boundaries do not leave seams under fractional transforms', () async {
    final whiteRecorder = ui.PictureRecorder();
    Canvas(whiteRecorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.white);
    final whitePicture = whiteRecorder.endRecording();
    final white = whitePicture.toImageSync(8, 8);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..translate(.37, .63)..scale(1.27);
    final clip = BoundedMapClip(
      Path()..addRect(const Rect.fromLTWH(-100, -100, 500, 500)),
      const Size(17.3, 23.7),
    );
    paintBoundedMapImage(canvas, white,
      destination: const Rect.fromLTWH(0, 0, 120, 100),
      target: const Rect.fromLTWH(0, 0, 120, 100),
      visibleBounds: const Rect.fromLTWH(0, 0, 120, 100), clip: clip,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 80);
    final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (var y = 2; y < 78; y++) {
      for (var x = 2; x < 78; x++) {
        expect(pixels.getUint8((y * 80 + x) * 4 + 3), 255,
            reason: 'Gap on an internal map cell edge at ($x, $y)');
      }
    }
    image.dispose(); picture.dispose(); white.dispose(); whitePicture.dispose();
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('Mie mask excludes the inland overhang in the coarse outline', () async {
    final prepared = await PreparedTerritory.load('24');
    final mask = prepared.path('pref', (p) => Offset(p.x, p.y));
    // Outside both the detailed municipalities and MLIT N03 Mie boundaries.
    // The old coarse prefecture outline incorrectly included this location.
    expect(mask.contains(const Offset(136.05192309050943, 34.657852)), isFalse);
    expect(mask.contains(const Offset(136.13, 34.768)), isTrue);
  }, timeout: const Timeout(Duration(seconds: 45)));

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
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.white);
    final whitePicture = recorder.endRecording();
    final white = whitePicture.toImageSync(8, 8);
    final maskTiles = BoundedMapClip(mask, const Size(80, 80));
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
              geographyIsClipped: true,
              children: [
                Positioned.fill(child: CustomPaint(painter: _BoundedImage(white, maskTiles))),
                const SizedBox.expand(),
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
    await tester.pumpWidget(const SizedBox());
    white.dispose();
    whitePicture.dispose();
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('dense Mie mask matches its geometry at Owase southern coast zoom', (
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
      (p) => Offset((p.x - 135.85) * 1000, (34.4 - p.y) * 1000),
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.white);
    final whitePicture = recorder.endRecording();
    final white = whitePicture.toImageSync(8, 8);
    final maskTiles = BoundedMapClip(mask, const Size(80, 80));
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
              geographyIsClipped: true,
              children: [
                Positioned.fill(child: CustomPaint(painter: _BoundedImage(white, maskTiles))),
                const SizedBox.expand(),
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
            reason: 'Dense Owase Mie clip differs at scene point $point',
          );
        }
      }
      expect(inside, greaterThan(20));
      expect(outside, greaterThan(20));
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    white.dispose();
    whitePicture.dispose();
  }, timeout: const Timeout(Duration(seconds: 45)));

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
  }, timeout: const Timeout(Duration(seconds: 45)));
}

class _CoastalOffice extends CustomPainter {
  const _CoastalOffice();
  @override
  void paint(Canvas canvas, Size size) =>
      paintOfficeSymbol(canvas, const Offset(88, 50), 1, isCity: true);
  @override
  bool shouldRepaint(_CoastalOffice old) => false;
}

class _BoundedImage extends CustomPainter {
  _BoundedImage(this.image, this.clip);
  final ui.Image image;
  final BoundedMapClip clip;
  @override
  void paint(Canvas canvas, Size size) => paintBoundedMapImage(
    canvas, image, destination: Offset.zero & size, target: Offset.zero & size,
    visibleBounds: Offset.zero & size, clip: clip,
  );
  @override
  bool shouldRepaint(_BoundedImage old) => old.image != image || old.clip != clip;
}

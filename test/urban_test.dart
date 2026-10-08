import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/urban.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('projection preserves polygon holes', () {
    final layer = UrbanLayer.fromJson({
      'areas': [
        [
          [
            [0, 0],
            [10, 0],
            [10, 10],
            [0, 10],
            [0, 0],
          ],
          [
            [3, 3],
            [7, 3],
            [7, 7],
            [3, 7],
            [3, 3],
          ],
        ],
      ],
    }, (p) => Offset(p.x * 2, p.y * 2));
    expect(layer.areas.contains(const Offset(2, 2)), isTrue);
    expect(layer.areas.contains(const Offset(10, 10)), isFalse);
    expect(layer.areas.getBounds(), const Rect.fromLTRB(0, 0, 20, 20));
  });
  test('building land is translucent and clipped', () async {
    final recorder = ui.PictureRecorder();
    final layer = UrbanLayer(
      Path()..addRect(const Rect.fromLTWH(0, 0, 30, 30)),
    );
    layer.paint(
      Canvas(recorder),
      Path()..addRect(const Rect.fromLTWH(5, 5, 20, 20)),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(30, 30);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(bytes.getUint8((10 * 30 + 10) * 4 + 3), 133);
    expect(bytes.getUint8((2 * 30 + 2) * 4 + 3), 0);
    image.dispose();
    picture.dispose();
  });
}

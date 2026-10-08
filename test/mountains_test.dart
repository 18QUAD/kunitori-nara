import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/mountains.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('moves overlapping text without moving the summit', () {
    final layer = MountainLayer(
      [MountainLabel('山', const Offset(50, 50))],
      summits: [MountainLabel('山', const Offset(50, 50))],
    );
    final recorder = ui.PictureRecorder();
    final occupied = <Rect>[];
    layer.paintLabels(
      Canvas(recorder),
      Path()..addRect(const Rect.fromLTWH(0, 0, 200, 200)),
      1,
      occupied,
    );
    expect(occupied, hasLength(2));
    expect(occupied.first.contains(const Offset(50, 50)), isTrue);
    expect(occupied.first.overlaps(occupied.last), isFalse);
    expect(layer.summits.single.point, const Offset(50, 50));
    recorder.endRecording().dispose();
  });

  test('summits use independent coordinates and never fall back to labels', () {
    final data = <String, dynamic>{
      'labels': [
        {
          'name': '山',
          'point': [1, 2],
        },
      ],
      'summits': [
        {
          'name': '山',
          'point': [3, 4],
        },
      ],
    };
    final layer = MountainLayer.fromJson(data, (p) => Offset(p.x * 2, p.y * 2));
    expect(layer.labels.single.point, const Offset(2, 4));
    expect(layer.summits.single.point, const Offset(6, 8));
    data.remove('summits');
    expect(
      MountainLayer.fromJson(data, (p) => Offset(p.x, p.y)).summits,
      isEmpty,
    );
  });

  test(
    'draws summit triangles and excludes points outside the visible region',
    () async {
      final layer = MountainLayer(
        [],
        summits: [
          MountainLabel('内', const Offset(20, 20)),
          MountainLabel('外', const Offset(60, 60)),
        ],
      );
      final recorder = ui.PictureRecorder();
      final occupied = <Rect>[];
      layer.paintLabels(
        Canvas(recorder),
        Path()..addRect(const Rect.fromLTWH(0, 0, 40, 40)),
        1,
        occupied,
      );
      expect(occupied, hasLength(1));
      expect(occupied.single.contains(const Offset(20, 20)), isTrue);
      final picture = recorder.endRecording();
      final image = await picture.toImage(80, 80);
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      expect(pixels.getUint8((20 * 80 + 20) * 4 + 3), greaterThan(0));
      expect(pixels.getUint8((60 * 80 + 60) * 4 + 3), 0);
      image.dispose();
      picture.dispose();
    },
  );
}

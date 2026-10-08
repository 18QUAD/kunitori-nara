import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/mountains.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('moves mountain names away from occupied labels', () {
    final layer = MountainLayer([MountainLabel('山', const Offset(50, 50))]);
    final recorder = ui.PictureRecorder();
    final occupied = <Rect>[const Rect.fromLTWH(45, 45, 10, 10)];
    layer.paintLabels(
      Canvas(recorder),
      Path()..addRect(const Rect.fromLTWH(0, 0, 200, 200)),
      1,
      occupied,
    );
    expect(occupied, hasLength(2));
    expect(occupied.first.contains(const Offset(50, 50)), isTrue);
    expect(occupied.first.overlaps(occupied.last), isFalse);
    recorder.endRecording().dispose();
  });

  test('only annotation coordinates determine mountain name positions', () {
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
  });

  test('legacy summit coordinates draw no markers', () async {
    final layer = MountainLayer.fromJson({
      'labels': [],
      'summits': [
        {
          'name': '内',
          'point': [20, 20],
        },
        {
          'name': '外',
          'point': [60, 60],
        },
      ],
    }, (p) => Offset(p.x, p.y));
    final recorder = ui.PictureRecorder();
    final occupied = <Rect>[];
    layer.paintLabels(
      Canvas(recorder),
      Path()..addRect(const Rect.fromLTWH(0, 0, 40, 40)),
      1,
      occupied,
    );
    expect(occupied, isEmpty);
    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 80);
    final pixels =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(pixels.buffer.asUint8List().every((byte) => byte == 0), isTrue);
    expect(pixels.getUint8((60 * 80 + 60) * 4 + 3), 0);
    image.dispose();
    picture.dispose();
  });
}

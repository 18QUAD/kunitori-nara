import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/mountains.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each prefecture loads its own bundled mountain annotations', () async {
    for (var i = 1; i <= 47; i++) {
      final id = i.toString().padLeft(2, '0');
      final layer = await MountainLayer.load(
        (p) => Offset(p.x, p.y),
        prefectureId: id,
      );
      expect(layer.labels, isNotEmpty, reason: id);
      expect(layer.naraOverview, id == '29');
      if (id != '29') {
        expect(layer.labels.any((label) => label.overview == true), isTrue);
      }
      if (id == '19') {
        expect(layer.labels.any((label) => label.name == '富士山'), isTrue);
        expect(layer.labels.any((label) => label.name == '若草山'), isFalse);
      }
    }
  });

  test('other prefectures show mountain names at prefecture scale', () {
    final layer = MountainLayer([
      MountainLabel('富士山', const Offset(500, 500), overview: true),
      MountainLabel('詳細の山名', const Offset(700, 500), overview: false),
    ], naraOverview: false);
    final recorder = ui.PictureRecorder();
    final occupied = <Rect>[];
    layer.paintLabels(
      Canvas(recorder),
      Path()..addRect(const Rect.fromLTWH(0, 0, 1000, 1000)),
      0.2,
      occupied,
    );
    expect(occupied, hasLength(1));
    recorder.endRecording().dispose();
  });

  test('offscreen mountain annotations do not occupy visible labels', () {
    final layer = MountainLayer([
      MountainLabel('画面外', const Offset(1000, 1000)),
      MountainLabel('画面内', const Offset(50, 50)),
    ], naraOverview: false);
    final recorder = ui.PictureRecorder();
    final occupied = <Rect>[];
    layer.paintLabels(
      Canvas(recorder),
      Path()..addRect(const Rect.fromLTWH(0, 0, 2000, 2000)),
      1,
      occupied,
      viewport: const Rect.fromLTWH(0, 0, 100, 100),
    );
    expect(occupied, hasLength(1));
    expect(occupied.single.center, const Offset(50, 50));
    recorder.endRecording().dispose();
  });

  test('prefecture annotations are still clipped to municipality holes', () {
    final layer = MountainLayer([
      MountainLabel('市外の山', const Offset(50, 50)),
    ], naraOverview: false);
    final clip =
        Path()
          ..fillType = ui.PathFillType.evenOdd
          ..addRect(const Rect.fromLTWH(0, 0, 200, 200))
          ..addRect(const Rect.fromLTWH(40, 40, 20, 20));
    final recorder = ui.PictureRecorder();
    final occupied = <Rect>[];
    layer.paintLabels(Canvas(recorder), clip, 1, occupied, municipal: true);
    expect(occupied, isEmpty);
    recorder.endRecording().dispose();
  });

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

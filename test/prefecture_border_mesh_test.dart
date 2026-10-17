import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/prefecture_border_mesh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cached national images preserve the single Osaka–Nara shared edge',
    () async {
      final mesh = PrefectureBorderMesh(
        ByteData.sublistView(
          File('assets/data/prefecture_border_mesh.bin').readAsBytesSync(),
        ),
        (math.Point<double> p) =>
            ui.Offset((p.x - 135.625) * 4096, (34.5 - p.y) * 4096),
      );
      expect(mesh.counts.length, 50571);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawPath(
        mesh.path(const ui.Rect.fromLTWH(0, 0, 512, 512), 1),
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..color = const ui.Color(0xffffffff)
          ..strokeWidth = 1.3,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(512, 512);
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var y = 120; y <= 124; y++) {
        var runs = 0, previous = false;
        for (var x = 180; x <= 310; x++) {
          final white = pixels.getUint8((y * 512 + x) * 4 + 3) >= 64;
          if (white && !previous) runs++;
          previous = white;
        }
        expect(
          runs,
          1,
          reason: 'Shared prefecture boundaries must not become parallel lines',
        );
      }
      image.dispose();
      picture.dispose();
    },
  );
}

import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_boundary.dart';

void main() {
  testWidgets('all map layers stay inside the administrative outline', (
    tester,
  ) async {
    final outline =
        Path()
          ..moveTo(0, 0)
          ..lineTo(100, 0)
          ..lineTo(0, 100)
          ..close();
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 100,
            height: 100,
            child: ClipPath(
              clipper: MapBoundaryClipper(outline),
              child: Stack(
                alignment: Alignment.topLeft,
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xff123456)),
                  ),
                  Positioned(
                    left: 80,
                    top: 80,
                    width: 20,
                    height: 20,
                    child: const ColoredBox(color: Color(0xffffffff)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      expect(bytes.getUint8((10 * 100 + 10) * 4 + 3), 255);
      // Inside the bounding rectangle, but outside the actual prefecture.
      expect(bytes.getUint8((90 * 100 + 90) * 4 + 3), 0);
      image.dispose();
    });
  });
}

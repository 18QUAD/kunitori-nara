import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/raster_geometry.dart';

void main() {
  test(
    'subpixel simplification removes dense straight vertices and keeps bends',
    () {
      final points = [
        for (var i = 0; i <= 1000; i++) Offset(i / 10, i == 500 ? 2 : 0),
      ];
      final result = simplifyRasterLine(points, 0.05);
      expect(result.length, lessThan(10));
      expect(result.first, points.first);
      expect(result.last, points.last);
      expect(result, contains(const Offset(50, 2)));
    },
  );
  test(
    'coast masks retain holes and exclude offscreen islands at every scale',
    () {
      List<Point<double>> ring(double x, double y, double size) => [
        Point(x, y),
        Point(x + size, y),
        Point(x + size, y + size),
        Point(x, y + size),
        Point(x, y),
      ];
      final mask = RasterCoastMask([
        [ring(0, 0, 100), ring(20, 20, 10)],
        [ring(200, 200, 10)],
      ], (p) => Offset(p.x, p.y));
      for (final density in [0.25, 1.0, 24.0, 300.0]) {
        final path = mask.path(const Rect.fromLTWH(0, 0, 100, 100), density);
        expect(path.contains(const Offset(10, 10)), isTrue);
        expect(path.contains(const Offset(25, 25)), isFalse);
        expect(path.contains(const Offset(205, 205)), isFalse);
        expect(path.computeMetrics().length, 2);
        path.reset();
      }
    },
  );
}

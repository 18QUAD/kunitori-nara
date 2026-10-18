import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Douglas–Peucker with an error bound in scene units. Used only while baking
/// a cached image; the source geometry and interactive town shapes stay exact.
List<Offset> simplifyRasterLine(List<Offset> points, double tolerance) {
  if (points.length < 3) return points;
  final keep = Uint8List(points.length);
  keep[0] = keep[points.length - 1] = 1;
  final pending = <int>[0, points.length - 1];
  final limit = tolerance * tolerance;
  while (pending.isNotEmpty) {
    final last = pending.removeLast(), first = pending.removeLast();
    final a = points[first], b = points[last];
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final length = dx * dx + dy * dy;
    var maximum = limit, selected = -1;
    for (var i = first + 1; i < last; i++) {
      final px = points[i].dx - a.dx, py = points[i].dy - a.dy;
      final t =
          length == 0 ? 0.0 : ((px * dx + py * dy) / length).clamp(0.0, 1.0);
      final ex = px - dx * t, ey = py - dy * t;
      final distance = ex * ex + ey * ey;
      if (distance > maximum) {
        maximum = distance;
        selected = i;
      }
    }
    if (selected < 0) continue;
    keep[selected] = 1;
    pending.addAll([first, selected, selected, last]);
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i] != 0) points[i],
  ];
}

/// The map projection is affine. Project two extrema instead of allocating a
/// projected point and two rectangles for every coastline vertex.
Rect rasterPolygonBounds(
  List<List<math.Point<double>>> polygon,
  Offset Function(math.Point<double>) project,
) {
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final ring in polygon) {
    for (final p in ring) {
      left = math.min(left, p.x);
      right = math.max(right, p.x);
      top = math.min(top, p.y);
      bottom = math.max(bottom, p.y);
    }
  }
  if (!left.isFinite) return Rect.zero;
  return Rect.fromPoints(
    project(math.Point(left, top)),
    project(math.Point(right, bottom)),
  );
}

/// Build only the coast contours needed by one cached 512px background cell.
/// The maximum displacement is 0.05 image pixels, including at deep zoom.
class RasterCoastMask {
  RasterCoastMask(List<List<List<math.Point<double>>>> polygons, this.project) {
    for (final polygon in polygons) {
      _parts.add((rasterPolygonBounds(polygon, project), polygon));
    }
  }
  final Offset Function(math.Point<double>) project;
  final _parts = <(Rect, List<List<math.Point<double>>>)>[];

  Path path(Rect rect, double density) {
    final result = Path()..fillType = PathFillType.evenOdd;
    final area = rect.inflate(1 / density);
    for (final (bounds, polygon) in _parts) {
      if (!bounds.overlaps(area)) continue;
      for (final ring in polygon) {
        result.addPolygon(
          simplifyRasterLine(ring.map(project).toList(), 0.05 / density),
          true,
        );
      }
    }
    return result;
  }
}

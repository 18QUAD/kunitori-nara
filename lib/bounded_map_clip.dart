import 'dart:ui';

/// CPU-clipped, geographically bounded paths avoid 16-bit GPU path indices.
/// The source boundary remains exact; only its draw regions are partitioned.
class BoundedMapClip {
  BoundedMapClip(this.boundary, this.cellSize, {this.capacity = 256, List<List<Offset>>? rings})
    : _rings = rings?.map((r) => (points: r, bounds: _ringBounds(r))).toList() {
    if (cellSize.isEmpty || !cellSize.width.isFinite || !cellSize.height.isFinite) {
      throw ArgumentError.value(cellSize, 'cellSize');
    }
  }
  final Path boundary;
  final Size cellSize;
  final int capacity;
  final List<({List<Offset> points, Rect bounds})>? _rings;
  final _cache = <(int, int), Path>{};

  Iterable<({Rect bounds, Path path})> cells(Rect area) sync* {
    final region = area.intersect(boundary.getBounds());
    if (region.isEmpty) return;
    final left = (region.left / cellSize.width).floor();
    final right = (region.right / cellSize.width).ceil();
    final top = (region.top / cellSize.height).floor();
    final bottom = (region.bottom / cellSize.height).ceil();
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final bounds = Rect.fromLTWH(
          x * cellSize.width, y * cellSize.height, cellSize.width, cellSize.height,
        );
        final key = (x, y);
        final path = _cache.remove(key) ?? _cellPath(bounds);
        _cache[key] = path;
        while (_cache.length > capacity) {
          _cache.remove(_cache.keys.first);
        }
        if (!path.getBounds().isEmpty) yield (bounds: bounds, path: path);
      }
    }
  }
  Path _cellPath(Rect bounds) {
    final rings = _rings;
    if (rings == null) {
      return Path.combine(PathOperation.intersect, boundary, Path()..addRect(bounds));
    }
    final path = Path()..fillType = boundary.fillType;
    for (final ring in rings) {
      if (!ring.bounds.overlaps(bounds)) continue;
      var points = ring.points;
      points = _edge(points, bounds.left, true, true);
      points = _edge(points, bounds.right, true, false);
      points = _edge(points, bounds.top, false, true);
      points = _edge(points, bounds.bottom, false, false);
      if (points.length < 3) continue;
      path.addPolygon(points, true);
    }
    return path;
  }

  static Rect _ringBounds(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    var left = points.first.dx, right = left;
    var top = points.first.dy, bottom = top;
    for (final p in points.skip(1)) {
      if (p.dx < left) left = p.dx;
      if (p.dx > right) right = p.dx;
      if (p.dy < top) top = p.dy;
      if (p.dy > bottom) bottom = p.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  // Sutherland-Hodgman clipping preserves each ring's winding and holes.
  // Concave components can meet along a cell edge; hard cell clipping keeps
  // those connecting edge segments out of the visible interior.
  static List<Offset> _edge(List<Offset> points, double limit, bool xAxis, bool greater) {
    if (points.isEmpty) return points;
    double coordinate(Offset p) => xAxis ? p.dx : p.dy;
    bool inside(Offset p) => greater ? coordinate(p) >= limit : coordinate(p) <= limit;
    final result = <Offset>[];
    var previous = points.last;
    var previousInside = inside(previous);
    for (final point in points) {
      final pointInside = inside(point);
      if (pointInside != previousInside) {
        final t = (limit - coordinate(previous)) / (coordinate(point) - coordinate(previous));
        result.add(xAxis
          ? Offset(limit, previous.dy + (point.dy - previous.dy) * t)
          : Offset(previous.dx + (point.dx - previous.dx) * t, limit));
      }
      if (pointInside) result.add(point);
      previous = point;
      previousInside = pointInside;
    }
    return result;
  }
}

/// Draw one prepared image through small clips, including parent-LOD crops.
void paintBoundedMapImage(
  Canvas canvas,
  Image image, {
  required Rect destination,
  required Rect target,
  required Rect visibleBounds,
  required BoundedMapClip clip,
}) {
  final region = target.intersect(visibleBounds);
  if (region.isEmpty) return;
  final paint = Paint()..filterQuality = FilterQuality.low;
  final source = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  canvas.save();
  canvas.clipRect(region, doAntiAlias: false);
  for (final cell in clip.cells(region)) {
    canvas.save();
    // Hard cell edges prevent antialiased seams between adjacent partitions.
    canvas.clipRect(cell.bounds, doAntiAlias: false);
    canvas.clipPath(cell.path, doAntiAlias: false);
    canvas.drawImageRect(image, source, destination, paint);
    canvas.restore();
  }
  canvas.restore();
}

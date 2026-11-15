import 'dart:ui';

/// CPU-clipped, geographically bounded paths avoid 16-bit GPU path indices.
/// The source boundary remains exact; only its draw regions are partitioned.
class BoundedMapClip {
  BoundedMapClip(this.boundary, this.cellSize, {this.capacity = 256}) {
    if (cellSize.isEmpty || !cellSize.width.isFinite || !cellSize.height.isFinite) {
      throw ArgumentError.value(cellSize, 'cellSize');
    }
  }
  final Path boundary;
  final Size cellSize;
  final int capacity;
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
        final path = _cache.remove(key) ?? Path.combine(
          PathOperation.intersect, boundary, Path()..addRect(bounds),
        );
        _cache[key] = path;
        while (_cache.length > capacity) {
          _cache.remove(_cache.keys.first);
        }
        if (!path.getBounds().isEmpty) yield (bounds: bounds, path: path);
      }
    }
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

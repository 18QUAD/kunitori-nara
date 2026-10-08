import 'package:flutter/painting.dart';

/// Retain only unnested contours for display strokes, including detached parts.
/// The original path remains the source of fills, hit tests and clipping.
Path exteriorOutline(Path source) {
  final contours = <({Path path, Rect bounds, Offset start})>[];
  for (final metric in source.computeMetrics()) {
    final start = metric.getTangentForOffset(0)?.position;
    if (start == null) continue;
    final path = metric.extractPath(0, metric.length)..close();
    contours.add((path: path, bounds: path.getBounds(), start: start));
  }
  // An enclosing contour's bounding box is always at least as large.
  contours.sort(
    (a, b) => (b.bounds.width * b.bounds.height).compareTo(
      a.bounds.width * a.bounds.height,
    ),
  );
  final exterior = <({Path path, Rect bounds, Offset start})>[];
  final outline = Path();
  for (final contour in contours) {
    if (exterior.any(
      (outer) =>
          outer.bounds.contains(contour.start) &&
          outer.path.contains(contour.start),
    )) {
      continue;
    }
    exterior.add(contour);
    outline.addPath(contour.path, Offset.zero);
  }
  return outline;
}

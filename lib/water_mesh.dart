import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';

/// Compact original water contours. Only the visible prefecture (or the sparse
/// national overview) is resident; paths are built on image-cache misses only.
class WaterMesh {
  WaterMesh(this.bytes, this.project) {
    if (bytes.getUint32(0, Endian.little) != 0x3141574b) {
      throw const FormatException('Invalid water mesh');
    }
    final count = bytes.getUint32(4, Endian.little);
    final originalScale = bytes.getFloat64(8, Endian.little);
    final a = project(const math.Point(135.0, 35.0));
    final b = project(const math.Point(135.0, 36.0));
    widthUnit = (a.dy - b.dy).abs() / originalScale;
    bounds = Float64List(count * 4);
    offsets = Uint32List(count);
    ringCounts = Uint32List(count);
    rivers = Uint8List(count);
    var offset = 16;
    for (var i = 0; i < count; i++) {
      final a = project(
        math.Point(
          bytes.getFloat32(offset, Endian.little),
          bytes.getFloat32(offset + 4, Endian.little),
        ),
      );
      final b = project(
        math.Point(
          bytes.getFloat32(offset + 8, Endian.little),
          bytes.getFloat32(offset + 12, Endian.little),
        ),
      );
      bounds[i * 4] = math.min(a.dx, b.dx);
      bounds[i * 4 + 1] = math.min(a.dy, b.dy);
      bounds[i * 4 + 2] = math.max(a.dx, b.dx);
      bounds[i * 4 + 3] = math.max(a.dy, b.dy);
      final rings = bytes.getUint32(offset + 16, Endian.little);
      rivers[i] = (rings & 0x80000000) == 0 ? 0 : 1;
      ringCounts[i] = rings & 0x7fffffff;
      offsets[i] = offset + 20;
      offset += 20;
      for (var r = 0; r < ringCounts[i]; r++) {
        offset += 4 + bytes.getUint32(offset, Endian.little) * 8;
      }
    }
    if (offset != bytes.lengthInBytes) {
      throw const FormatException('Truncated water mesh');
    }
  }

  final ByteData bytes;
  final Offset Function(math.Point<double>) project;
  late final Float64List bounds;
  late final Uint32List offsets, ringCounts;
  late final Uint8List rivers;
  late final double widthUnit;

  static Future<WaterMesh> load(
    String id,
    Offset Function(math.Point<double>) project,
  ) async => WaterMesh(
    await rootBundle.load('assets/data/water_mesh/$id.bin'),
    project,
  );

  void paint(Canvas canvas, Rect rect, double density) {
    final view = rect.inflate(0.625 * widthUnit / 2 + 2 / density);
    final paths = <(Path, bool)>[];
    for (var i = 0; i < offsets.length; i++) {
      final j = i * 4;
      if (bounds[j + 2] < view.left ||
          bounds[j] > view.right ||
          bounds[j + 3] < view.top ||
          bounds[j + 1] > view.bottom) {
        continue;
      }
      final path = Path()..fillType = PathFillType.evenOdd;
      var offset = offsets[i];
      for (var r = 0; r < ringCounts[i]; r++) {
        final count = bytes.getUint32(offset, Endian.little);
        offset += 4;
        for (var p = 0; p < count; p++) {
          final point = project(
            math.Point(
              bytes.getInt32(offset, Endian.little) / 1000000,
              bytes.getInt32(offset + 4, Endian.little) / 1000000,
            ),
          );
          if (p == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
          offset += 8;
        }
        if (rivers[i] == 0) path.close();
      }
      paths.add((path, rivers[i] != 0));
    }
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    stroke
      ..color = const Color(0xff123d59)
      ..strokeWidth = 0.625 * widthUnit;
    for (final (path, _) in paths) {
      canvas.drawPath(path, stroke);
    }
    stroke
      ..color = const Color(0xff79d9ff)
      ..strokeWidth = 0.375 * widthUnit;
    for (final (path, river) in paths) {
      canvas.drawPath(path, stroke);
      if (!river) {
        canvas.drawPath(path, Paint()..color = const Color(0xff79d9ff));
      }
    }
    // Canvas records its own path data. Release these temporary native paths
    // after the last draw instead of waiting for JS garbage collection.
    for (final (path, _) in paths) {
      path.reset();
    }
  }
}

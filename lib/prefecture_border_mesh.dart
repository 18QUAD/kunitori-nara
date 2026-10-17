import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';

/// The same shared line network as the offline national borders. One compact
/// buffer belongs to the visible national map; no detailed prefecture is loaded.
class PrefectureBorderMesh {
  PrefectureBorderMesh(this.bytes, this.project) {
    if (bytes.getUint32(0, Endian.little) != 0x3152424b) {
      throw const FormatException('Invalid prefecture border mesh');
    }
    final count = bytes.getUint32(4, Endian.little);
    bounds = Float64List(count * 4);
    offsets = Uint32List(count);
    counts = Uint32List(count);
    var offset = 8;
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
      counts[i] = bytes.getUint32(offset + 16, Endian.little);
      offsets[i] = offset + 20;
      offset += 20 + counts[i] * 8;
    }
    if (offset != bytes.lengthInBytes) {
      throw const FormatException('Truncated prefecture border mesh');
    }
  }
  final ByteData bytes;
  final Offset Function(math.Point<double>) project;
  late final Float64List bounds;
  late final Uint32List offsets, counts;

  static Future<PrefectureBorderMesh> load(
    Offset Function(math.Point<double>) project,
  ) async => PrefectureBorderMesh(
    await rootBundle.load('assets/data/prefecture_border_mesh.bin'),
    project,
  );

  Path path(Rect rect, double density) {
    final path = Path();
    final area = rect.inflate(2 / density);
    final tolerance = 0.2 / density;
    for (var i = 0; i < counts.length; i++) {
      final j = i * 4;
      if (bounds[j + 2] < area.left ||
          bounds[j] > area.right ||
          bounds[j + 3] < area.top ||
          bounds[j + 1] > area.bottom) {
        continue;
      }
      Offset? previous;
      for (var p = 0; p < counts[i]; p++) {
        final offset = offsets[i] + p * 8;
        final point = project(
          math.Point(
            bytes.getInt32(offset, Endian.little) / 1000000,
            bytes.getInt32(offset + 4, Endian.little) / 1000000,
          ),
        );
        if (previous == null) {
          path.moveTo(point.dx, point.dy);
        } else if ((point - previous).distance < tolerance &&
            p != counts[i] - 1) {
          continue;
        } else {
          path.lineTo(point.dx, point.dy);
        }
        previous = point;
      }
    }
    return path;
  }
}

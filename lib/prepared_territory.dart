import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';

/// Offline-unioned town contours. The directory allows unneeded towns to be
/// skipped without parsing any coordinates or census JSON.
class PreparedTerritory {
  PreparedTerritory._(this.bytes) {
    if (bytes.getUint32(0, Endian.little) != 0x34544e4b) {
      throw const FormatException('Invalid prepared territory');
    }
    var offset = 8;
    final count = bytes.getUint32(4, Endian.little);
    for (var i = 0; i < count; i++) {
      final length = bytes.getUint8(offset++);
      final id = String.fromCharCodes(
        Uint8List.view(bytes.buffer, bytes.offsetInBytes + offset, length),
      );
      offset += length;
      final start = bytes.getUint32(offset, Endian.little);
      final size = bytes.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (start + size > bytes.lengthInBytes || entries.containsKey(id)) {
        throw const FormatException('Invalid prepared territory entry');
      }
      entries[id] = (start: start, size: size);
    }
  }
  static Future<PreparedTerritory> load(String pref) async =>
      PreparedTerritory._(
        await rootBundle.load('assets/data/national_territories/$pref.bin'),
      );
  final ByteData bytes;
  final entries = <String, ({int start, int size})>{};

  List<List<List<Point<double>>>> polygons(String id) {
    final entry = entries[id];
    if (entry == null) throw FormatException('Missing prepared town $id');
    var offset = entry.start;
    int uint() {
      final n = bytes.getUint32(offset, Endian.little);
      offset += 4;
      return n;
    }

    final result = <List<List<Point<double>>>>[];
    final count = uint();
    for (var p = 0; p < count; p++) {
      final rings = <List<Point<double>>>[];
      final ringCount = uint();
      for (var r = 0; r < ringCount; r++) {
        final mode = bytes.getUint8(offset++);
        if (mode > 1) {
          throw const FormatException('Invalid coordinate encoding');
        }
        final points = uint();
        final xy = Float64List(points * 2);
        var x = 0, y = 0;
        for (var i = 0; i < points; i++) {
          if (mode == 1) {
            x += bytes.getInt32(offset, Endian.little);
            y += bytes.getInt32(offset + 4, Endian.little);
            offset += 8;
            xy[i * 2] = x / 1e6;
            xy[i * 2 + 1] = y / 1e6;
          } else {
            xy[i * 2] = bytes.getFloat64(offset, Endian.little);
            xy[i * 2 + 1] = bytes.getFloat64(offset + 8, Endian.little);
            offset += 16;
          }
        }
        rings.add(_Ring(xy));
      }
      result.add(rings);
    }
    if (offset != entry.start + entry.size) {
      throw const FormatException('Prepared contour length mismatch');
    }
    return result;
  }

  Path path(String id, Offset Function(Point<double>) project) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in polygons(id)) {
      for (final ring in polygon) {
        if (ring.isEmpty) continue;
        final first = project(ring.first);
        path.moveTo(first.dx, first.dy);
        for (final point in ring.skip(1)) {
          final p = project(point);
          path.lineTo(p.dx, p.dy);
        }
        path.close();
      }
    }
    return path;
  }
}

class _Ring extends ListBase<Point<double>> {
  _Ring(this.xy);
  final Float64List xy;
  @override
  int get length => xy.length ~/ 2;
  @override
  set length(int value) => throw UnsupportedError('Read-only geometry');
  @override
  Point<double> operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return Point(xy[index * 2], xy[index * 2 + 1]);
  }

  @override
  void operator []=(int index, Point<double> value) =>
      throw UnsupportedError('Read-only geometry');
}

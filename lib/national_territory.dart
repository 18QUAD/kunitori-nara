import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'diagnostics.dart';

/// Decode only requested town rows, using a small byte-offset index into the
/// already downloaded census assets. No full prefecture JSON tree, Town objects,
/// parent outlines or temporary Point lists are constructed. Coordinates stay exact.
Future<Map<String, Path>> loadNationalTerritory({
  required String prefecture,
  required Set<String> towns,
  required Map<String, String> sourceToTown,
  required Offset Function(Point<double>) project,
  required bool Function() isCurrent,
}) async {
  recordDiagnostic('national_territory_start', {
    'territoryPrefecture': prefecture,
    'requestedTowns': towns.length,
  });
  final paths = <String, Path>{};
  try {
    final index = await rootBundle.load(
      'assets/data/national_territories/$prefecture.bin',
    );
    if (!isCurrent()) return paths;
    if (index.getUint32(0, Endian.little) != 0x33544e4b) {
      throw const FormatException('Invalid national territory index');
    }
    final bytes = await rootBundle.load(
      prefecture == '29'
          ? 'assets/data/nara.json'
          : 'assets/data/prefectures/$prefecture.json',
    );
    if (!isCurrent()) return paths;
    if (index.getUint32(4, Endian.little) != bytes.lengthInBytes) {
      throw const FormatException('National territory source mismatch');
    }
    final rows = index.getUint32(8, Endian.little);
    var offset = 12, decodedRows = 0, vertices = 0;
    for (var row = 0; row < rows; row++) {
      final length = index.getUint8(offset++);
      final source = String.fromCharCodes(
        Uint8List.view(index.buffer, index.offsetInBytes + offset, length),
      );
      offset += length;
      final start = index.getUint32(offset, Endian.little);
      final size = index.getUint32(offset + 4, Endian.little);
      offset += 8;
      final id = sourceToTown[source];
      if (id == null || !towns.contains(id)) continue;
      final data =
          jsonDecode(
                utf8.decode(
                  Uint8List.view(
                    bytes.buffer,
                    bytes.offsetInBytes + start,
                    size,
                  ),
                ),
              )
              as Map<String, dynamic>;
      if (data['id'] != source) {
        throw const FormatException('Town index mismatch');
      }
      final path = paths.putIfAbsent(
        id,
        () => Path()..fillType = PathFillType.evenOdd,
      );
      for (final polygon in data['polygons'] as List) {
        for (final ring in polygon as List) {
          var first = true;
          for (final point in ring as List) {
            final p = project(
              Point((point[0] as num).toDouble(), (point[1] as num).toDouble()),
            );
            if (first) {
              path.moveTo(p.dx, p.dy);
              first = false;
            } else {
              path.lineTo(p.dx, p.dy);
            }
            vertices++;
          }
          if (!first) path.close();
        }
      }
      decodedRows++;
    }
    if (offset != index.lengthInBytes || paths.length != towns.length) {
      throw const FormatException('National territory coverage mismatch');
    }
    recordDiagnostic('national_territory_done', {
      'territoryPrefecture': prefecture,
      'territoryBytes': bytes.lengthInBytes,
      'territoryTowns': paths.length,
      'territoryRows': decodedRows,
      'territorySkippedRows': rows - decodedRows,
      'territoryVertices': vertices,
    });
    return paths;
  } catch (error) {
    for (final path in paths.values) {
      path.reset();
    }
    recordDiagnostic('national_territory_error', {
      'territoryPrefecture': prefecture,
      'error': error.toString(),
    });
    rethrow;
  }
}

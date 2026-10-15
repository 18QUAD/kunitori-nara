import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// MLIT building-land meshes; Nara retains its original dissolved vectors.
class UrbanLayer {
  UrbanLayer(this.areas, {this.rasters = const []});
  final Path areas;
  final List<UrbanRaster> rasters;
  static Map<String, dynamic>? _index;

  void dispose() {
    for (final raster in rasters) {
      raster.image.dispose();
    }
  }

  // Cool lavender stays distinct from the warm gold used for reachable land.
  static const color = Color(0x85B6A0F5);

  static Future<UrbanLayer> load(
    Offset Function(math.Point<double>) project, {
    String prefectureId = '29',
    bool national = false,
  }) async {
    if (national || prefectureId != '29') {
      final rasters = <UrbanRaster>[];
      try {
        final List<Map<String, dynamic>> rows;
        if (national) {
          rows = [
            jsonDecode(
                  await rootBundle.loadString(
                    'assets/data/urban/national.json',
                  ),
                )
                as Map<String, dynamic>,
          ];
        } else {
          final index =
              _index ??=
                  jsonDecode(
                        await rootBundle.loadString(
                          'assets/data/urban/index.json',
                        ),
                      )
                      as Map<String, dynamic>;
          final ids =
              (index['prefectures'][prefectureId] as List)
                  .cast<String>()
                  .toSet();
          rows =
              (index['tiles'] as List)
                  .cast<Map<String, dynamic>>()
                  .where((row) => ids.contains(row['id']))
                  .toList();
        }
        Future<void> decode(Map<String, dynamic> row) async {
          final file = national ? 'national' : row['id'];
          final bytes = await rootBundle.load('assets/data/urban/$file.png');
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
          try {
            final image = (await codec.getNextFrame()).image;
            rasters.add(
              UrbanRaster(
                image,
                Rect.fromPoints(
                  project(
                    math.Point(
                      (row['west'] as num).toDouble(),
                      (row['north'] as num).toDouble(),
                    ),
                  ),
                  project(
                    math.Point(
                      (row['east'] as num).toDouble(),
                      (row['south'] as num).toDouble(),
                    ),
                  ),
                ),
              ),
            );
          } finally {
            codec.dispose();
          }
        }

        for (var start = 0; start < rows.length; start += 16) {
          await Future.wait(rows.skip(start).take(16).map(decode));
        }
        if (rasters.isEmpty) throw const FormatException('市街地データがありません。');
        return UrbanLayer(Path(), rasters: rasters);
      } catch (_) {
        for (final raster in rasters) {
          raster.image.dispose();
        }
        rethrow;
      }
    }
    return UrbanLayer.fromJson(
      jsonDecode(await rootBundle.loadString('assets/data/nara_urban.json'))
          as Map<String, dynamic>,
      project,
    );
  }

  factory UrbanLayer.fromJson(
    Map<String, dynamic> json,
    Offset Function(math.Point<double>) project,
  ) {
    final areas = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in json['areas'] as List) {
      for (final ring in polygon as List) {
        var first = true;
        for (final coordinate in ring as List) {
          final p = project(
            math.Point(
              (coordinate[0] as num).toDouble(),
              (coordinate[1] as num).toDouble(),
            ),
          );
          if (first) {
            areas.moveTo(p.dx, p.dy);
            first = false;
          } else {
            areas.lineTo(p.dx, p.dy);
          }
        }
        areas.close();
      }
    }
    return UrbanLayer(areas);
  }

  void paint(Canvas canvas, Path clip) {
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawPath(areas, Paint()..color = color);
    for (final raster in rasters) {
      canvas.drawImageRect(
        raster.image,
        Rect.fromLTWH(
          0,
          0,
          raster.image.width.toDouble(),
          raster.image.height.toDouble(),
        ),
        raster.bounds,
        Paint()
          ..colorFilter = const ColorFilter.mode(color, BlendMode.srcIn)
          ..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();
  }
}

class UrbanRaster {
  UrbanRaster(this.image, this.bounds);
  final ui.Image image;
  final Rect bounds;
}

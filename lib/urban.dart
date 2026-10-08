import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// MLIT 2021 building land meshes, dissolved and clipped to Nara.
class UrbanLayer {
  UrbanLayer(this.areas);
  final Path areas;
  static const color = Color(0x85F3B7CC);

  static Future<UrbanLayer> load(
    Offset Function(math.Point<double>) project,
  ) async {
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
    canvas.restore();
  }
}

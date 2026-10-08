import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WaterLabel {
  WaterLabel(this.name, this.point);
  final String name;
  final Offset point;
}

/// Surface water from GSI vector tiles, projected once into map coordinates.
class WaterLayer {
  WaterLayer(this.rivers, this.areas, this.labels);
  final Path rivers, areas;
  final List<WaterLabel> labels;

  static Future<WaterLayer> load(
    Offset Function(math.Point<double>) project,
  ) async {
    final json =
        jsonDecode(await rootBundle.loadString('assets/data/nara_water.json'))
            as Map<String, dynamic>;
    return WaterLayer.fromJson(json, project);
  }

  factory WaterLayer.fromJson(
    Map<String, dynamic> json,
    Offset Function(math.Point<double>) project,
  ) {
    Offset point(dynamic p) =>
        project(math.Point((p[0] as num).toDouble(), (p[1] as num).toDouble()));
    void addLine(Path path, List<dynamic> points, {bool close = false}) {
      if (points.isEmpty) return;
      final start = point(points.first);
      path.moveTo(start.dx, start.dy);
      for (final p in points.skip(1)) {
        final v = point(p);
        path.lineTo(v.dx, v.dy);
      }
      if (close) path.close();
    }

    final rivers = Path();
    for (final line in json['lines'] as List) {
      addLine(rivers, line as List);
    }
    // Even-odd rings preserve islands in lakes/reservoirs.
    final areas = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in json['areas'] as List) {
      for (final ring in polygon as List) {
        addLine(areas, ring as List, close: true);
      }
    }
    return WaterLayer(rivers, areas, [
      for (final label in json['labels'] as List)
        WaterLabel(label['name'] as String, point(label['point'])),
    ]);
  }

  void paint(Canvas canvas, Path clip, double zoom) {
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawPath(areas, Paint()..color = const Color(0xFF53B8E6));
    canvas.drawPath(
      rivers,
      Paint()
        ..color = const Color(0xFF71C9EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (zoom < 0.5 ? 0.65 : 1.1) / zoom
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void paintLabels(Canvas canvas, Path clip, double zoom, List<Rect> occupied) {
    if (zoom < 0.65) return;
    for (final label in labels) {
      if (!clip.contains(label.point)) continue;
      final text = TextPainter(
        text: TextSpan(
          text: label.name,
          style: TextStyle(
            fontFamily: 'NotoSansJP',
            fontSize: 11 / zoom,
            color: const Color(0xFF8EDBFF),
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Color(0xFF102A32), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
        center: label.point,
        width: text.width + 8 / zoom,
        height: text.height + 4 / zoom,
      );
      if (occupied.any((r) => r.overlaps(rect))) continue;
      occupied.add(rect);
      text.paint(canvas, label.point - Offset(text.width / 2, text.height / 2));
    }
  }
}

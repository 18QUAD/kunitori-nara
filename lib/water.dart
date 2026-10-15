import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'map_label.dart';

class WaterLabel {
  WaterLabel(this.name, this.point, {this.detail = false});
  final String name;
  final Offset point;
  final bool detail;
}

/// Surface water from GSI vector tiles, projected once into map coordinates.
class WaterLayer {
  WaterLayer(this.rivers, this.areas, this.labels, {this.overview = false});
  final bool overview;
  final Path rivers, areas;
  final List<WaterLabel> labels;

  static Future<WaterLayer> load(
    Offset Function(math.Point<double>) project, {
    String prefectureId = '29',
    bool national = false,
  }) async {
    final json =
        jsonDecode(
              await rootBundle.loadString(
                national
                    ? 'assets/data/water/national.json'
                    : prefectureId == '29'
                    ? 'assets/data/nara_water.json'
                    : 'assets/data/water/$prefectureId.json',
              ),
            )
            as Map<String, dynamic>;
    return WaterLayer.fromJson(json, project, overview: national);
  }

  factory WaterLayer.fromJson(
    Map<String, dynamic> json,
    Offset Function(math.Point<double>) project, {
    bool overview = false,
  }) {
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
        WaterLabel(
          label['name'] as String,
          point(label['point']),
          detail: label['detail'] == true,
        ),
    ], overview: overview);
  }

  void paint(Canvas canvas, Path clip) {
    canvas.save();
    canvas.clipPath(clip);
    // Widths are in map coordinates, so the canvas transform scales the water
    // and its outline together. At 4x these appear as 1.5px and 2.5px strokes.
    final widthFactor = overview ? 0.24 : 1.0;
    for (final path in overview ? [rivers] : [areas, rivers]) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF123D59)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.625 * widthFactor
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    if (!overview) {
      canvas.drawPath(
        areas,
        Paint()
          ..color = const Color(0xFF79D9FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.375 * widthFactor
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.drawPath(areas, Paint()..color = const Color(0xFF79D9FF));
    canvas.drawPath(
      rivers,
      Paint()
        ..color = const Color(0xFF79D9FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.375 * widthFactor
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void paintLabels(
    Canvas canvas,
    Path clip,
    double zoom,
    List<Rect> occupied, {
    bool municipal = false,
    Rect? viewport,
  }) {
    if (!municipal && zoom < 0.65) return;
    final placed = <String, List<Offset>>{};
    for (final label in labels) {
      if (viewport != null &&
          !viewport.inflate(180 / zoom).contains(label.point)) {
        continue;
      }
      if (label.detail && !municipal) continue;
      if (!clip.contains(label.point)) continue;
      if ((placed[label.name] ?? []).any(
        (p) => (p - label.point).distance * zoom < 140,
      )) {
        continue;
      }
      final text = TextPainter(
        text: TextSpan(
          text: label.name,
          style: TextStyle(
            fontFamily: 'NotoSansJP',
            fontSize: 11 / zoom,
            color: const Color(0xFFBDEEFF),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Try nearby positions before omitting a name that overlaps a town label.
      for (final shift in const [
        Offset.zero,
        Offset(0, -16),
        Offset(0, 16),
        Offset(-18, 0),
        Offset(18, 0),
        Offset(-18, -16),
        Offset(18, -16),
        Offset(-18, 16),
        Offset(18, 16),
      ]) {
        final center = label.point + shift / zoom;
        final rect = Rect.fromCenter(
          center: center,
          width: text.width + 8 / zoom,
          height: text.height + 4 / zoom,
        );
        if (!clip.contains(center) || occupied.any((r) => r.overlaps(rect))) {
          continue;
        }
        occupied.add(rect);
        placed.putIfAbsent(label.name, () => []).add(center);
        paintMapLabel(
          canvas,
          text,
          center - Offset(text.width / 2, text.height / 2),
          zoom,
        );
        break;
      }
    }
  }
}

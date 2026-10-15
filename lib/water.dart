import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'map_label.dart';
import 'coastal_assets.dart';

class WaterLabel {
  WaterLabel(this.name, this.point, {this.detail = false});
  final String name;
  final Offset point;
  final bool detail;
}

/// Surface water from GSI vector tiles, projected once into map coordinates.
class WaterLayer {
  WaterLayer(
    this.rivers,
    this.areas,
    this.labels, {
    this.overview = false,
    this.preclippedLabels = false,
    this.outlineAreas = true,
    this.countyAreas,
    this.buckets = const {},
  });
  final bool outlineAreas;
  final Path? countyAreas;
  final Map<math.Point<int>, WaterBucket> buckets;
  final bool overview;
  final bool preclippedLabels;
  final Path rivers, areas;
  final List<WaterLabel> labels;

  /// Small name-only asset; fixed water geometry is pre-rendered offline.
  static Future<WaterLayer> loadLabels(
    Offset Function(math.Point<double>) project, {
    String prefectureId = '29',
    bool national = false,
  }) async => WaterLayer.fromJson(
    jsonDecode(
      await loadCoastalAsset(
        'assets/data/map_labels/${national ? 'national' : prefectureId}.json',
      ),
    ),
    project,
    preclippedLabels: national || prefectureId != '29',
  );

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
    return WaterLayer.fromJson(
      json,
      project,
      overview: national,
      spatial: !national && prefectureId != '29',
      outlineAreas: !national && prefectureId == '29',
    );
  }

  factory WaterLayer.fromJson(
    Map<String, dynamic> json,
    Offset Function(math.Point<double>) project, {
    bool overview = false,
    bool preclippedLabels = false,
    bool spatial = false,
    bool outlineAreas = true,
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

    final buckets = <math.Point<int>, WaterBucket>{};
    void distribute(Path part, bool waterArea) {
      if (!spatial) return;
      final bounds = part.getBounds();
      for (
        var x = (bounds.left / 100).floor();
        x <= (bounds.right / 100).floor();
        x++
      ) {
        for (
          var y = (bounds.top / 100).floor();
          y <= (bounds.bottom / 100).floor();
          y++
        ) {
          final key = math.Point(x, y);
          final bucket = buckets.putIfAbsent(
            key,
            () => WaterBucket(Rect.fromLTWH(x * 100.0, y * 100.0, 100, 100)),
          );
          (waterArea ? bucket.areas : bucket.rivers).addPath(part, Offset.zero);
        }
      }
    }

    final rivers = Path();
    for (final line in json['lines'] as List) {
      final part = Path();
      addLine(part, line as List);
      rivers.addPath(part, Offset.zero);
      distribute(part, false);
    }
    Path polygons(List<dynamic> polygons, {bool distributeParts = false}) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final polygon in polygons) {
        final part = Path()..fillType = PathFillType.evenOdd;
        for (final ring in polygon as List) {
          addLine(part, ring as List, close: true);
        }
        path.addPath(part, Offset.zero);
        if (distributeParts) distribute(part, true);
      }
      return path;
    }

    final areas = polygons(json['areas'] as List, distributeParts: true);
    final countyAreas =
        json['overviewAreas'] == null
            ? null
            : polygons(json['overviewAreas'] as List);
    return WaterLayer(
      rivers,
      areas,
      [
        for (final label in json['labels'] as List)
          WaterLabel(
            label['name'] as String,
            point(label['point']),
            detail: label['detail'] == true,
          ),
      ],
      overview: overview,
      preclippedLabels: preclippedLabels,
      outlineAreas: outlineAreas,
      countyAreas: countyAreas,
      buckets: buckets,
    );
  }

  void paint(
    Canvas canvas,
    Path clip, {
    bool municipal = true,
    Rect? viewport,
  }) {
    canvas.save();
    canvas.clipPath(clip);
    if (municipal && viewport != null && buckets.isNotEmpty) {
      for (final bucket in buckets.values) {
        if (!bucket.bounds.overlaps(viewport.inflate(2))) continue;
        canvas.save();
        canvas.clipRect(bucket.bounds);
        _paintPaths(canvas, bucket.rivers, bucket.areas);
        canvas.restore();
      }
    } else {
      _paintPaths(canvas, rivers, !municipal ? countyAreas ?? areas : areas);
    }
    canvas.restore();
  }

  void _paintPaths(Canvas canvas, Path rivers, Path areas) {
    // Widths are in map coordinates, so the canvas transform scales the water
    // and its outline together. At 4x these appear as 1.5px and 2.5px strokes.
    final widthFactor = overview ? 0.24 : 1.0;
    for (final path in overview || !outlineAreas ? [rivers] : [areas, rivers]) {
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
    if (!overview && outlineAreas) {
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
    final clipBounds = clip.getBounds();
    final visible = viewport?.inflate(64 / zoom);
    var displayed = 0;
    var geometryChecks = 0;
    // Nationwide names were already clipped by the importer. Municipal views
    // still check the selected city's outline, with a bounded placement budget.
    final needsClip = municipal || !preclippedLabels;
    for (final label in labels) {
      if (displayed >= 48) break;
      if (visible != null && !visible.contains(label.point)) {
        continue;
      }
      if (label.detail && !municipal) continue;
      if ((placed[label.name] ?? []).any(
        (p) => (p - label.point).distance * zoom < 140,
      )) {
        continue;
      }
      if (!clipBounds.contains(label.point)) continue;
      if (needsClip) {
        if (++geometryChecks > 96) break;
        if (!clip.contains(label.point)) continue;
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
        if (!clipBounds.contains(center) ||
            occupied.any((r) => r.overlaps(rect)) ||
            (needsClip && !clip.contains(center))) {
          continue;
        }
        displayed++;
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
      text.dispose();
    }
  }
}

class WaterBucket {
  WaterBucket(this.bounds);
  final Rect bounds;
  final Path areas = Path()..fillType = PathFillType.evenOdd;
  final Path rivers = Path();
}

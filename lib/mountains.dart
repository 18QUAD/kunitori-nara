import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'map_label.dart';

class MountainLabel {
  MountainLabel(this.name, this.point);
  final String name;
  final Offset point;
}

/// Annotation positions and independently sourced summit coordinates.
class MountainLayer {
  MountainLayer(this.labels, {this.summits = const []});
  final List<MountainLabel> labels;
  final List<MountainLabel> summits;
  static const overviewNames = [
    '八経ヶ岳',
    '大台ヶ原山',
    '釈迦ヶ岳',
    '金剛山',
    '生駒山',
    '若草山',
    '山上ヶ岳',
    '三峰山',
    '玉置山',
    '三輪山',
    '伯母子岳',
    '高見山',
  ];

  static Future<MountainLayer> load(
    Offset Function(math.Point<double>) project,
  ) async {
    final json =
        jsonDecode(
              await rootBundle.loadString('assets/data/nara_mountains.json'),
            )
            as Map<String, dynamic>;
    return MountainLayer.fromJson(json, project);
  }

  factory MountainLayer.fromJson(
    Map<String, dynamic> json,
    Offset Function(math.Point<double>) project,
  ) {
    final labels = [
      for (final l in json['labels'] as List)
        MountainLabel(
          l['name'] as String,
          project(
            math.Point(
              (l['point'][0] as num).toDouble(),
              (l['point'][1] as num).toDouble(),
            ),
          ),
        ),
    ];
    int priority(MountainLabel label) {
      final index = overviewNames.indexOf(label.name);
      return index < 0 ? overviewNames.length : index;
    }

    labels.sort((a, b) {
      final order = priority(a).compareTo(priority(b));
      return order == 0 ? a.name.compareTo(b.name) : order;
    });
    return MountainLayer(
      labels,
      summits: [
        for (final s in (json['summits'] as List? ?? const []))
          MountainLabel(
            s['name'] as String,
            project(
              math.Point(
                (s['point'][0] as num).toDouble(),
                (s['point'][1] as num).toDouble(),
              ),
            ),
          ),
      ],
    );
  }

  void paintLabels(Canvas canvas, Path clip, double zoom, List<Rect> occupied) {
    // Never infer a summit from a cartographic label position.
    canvas.save();
    canvas.clipPath(clip);
    for (final summit in summits) {
      if (!clip.contains(summit.point)) continue;
      final p = summit.point;
      final marker =
          Path()
            ..moveTo(p.dx, p.dy - 5 / zoom)
            ..lineTo(p.dx + 4.5 / zoom, p.dy + 3.5 / zoom)
            ..lineTo(p.dx - 4.5 / zoom, p.dy + 3.5 / zoom)
            ..close();
      canvas.drawPath(marker, Paint()..color = const Color(0xFFFFF1C2));
      canvas.drawPath(
        marker,
        Paint()
          ..color = const Color(0xFF101C2B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / zoom
          ..strokeJoin = StrokeJoin.round,
      );
      occupied.add(marker.getBounds().inflate(2 / zoom));
    }
    canvas.restore();
    for (final label in labels) {
      if (zoom < 0.65 && !overviewNames.contains(label.name)) continue;
      if (!clip.contains(label.point)) continue;
      final text = TextPainter(
        text: TextSpan(
          text: label.name,
          style: TextStyle(
            fontFamily: 'NotoSansJP',
            fontSize: 11 / zoom,
            color: const Color(0xFFFFF1C2),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Move only the text when a summit or another label occupies its anchor.
      for (final offset in [
        Offset.zero,
        Offset(0, -(text.height / 2 + 10 / zoom)),
        Offset(0, text.height / 2 + 10 / zoom),
        Offset(text.width / 2 + 10 / zoom, 0),
        Offset(-(text.width / 2 + 10 / zoom), 0),
      ]) {
        final center = label.point + offset;
        if (!clip.contains(center)) continue;
        final rect = Rect.fromCenter(
          center: center,
          width: text.width + 8 / zoom,
          height: text.height + 4 / zoom,
        );
        if (occupied.any((r) => r.overlaps(rect))) continue;
        occupied.add(rect);
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

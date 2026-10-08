import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MountainLabel {
  MountainLabel(this.name, this.point);
  final String name;
  final Offset point;
}

/// GSI mountain annotation positions; these do not represent surveyed summits.
class MountainLayer {
  MountainLayer(this.labels);
  final List<MountainLabel> labels;
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
    return MountainLayer(labels);
  }

  void paintLabels(Canvas canvas, Path clip, double zoom, List<Rect> occupied) {
    for (final label in labels) {
      if (zoom < 0.65 && !overviewNames.contains(label.name)) continue;
      if (!clip.contains(label.point)) continue;
      final text = TextPainter(
        text: TextSpan(
          text: label.name,
          style: TextStyle(
            fontFamily: 'NotoSansJP',
            fontSize: 11 / zoom,
            color: const Color(0xFFFFDE9A),
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

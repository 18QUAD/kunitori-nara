import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'coastal_assets.dart';
import 'map_label.dart';

class MountainLabel {
  MountainLabel(this.name, this.point, {this.overview});
  final String name;
  final Offset point;
  final bool? overview;
}

/// Mountain annotation positions; only names are displayed.
class MountainLayer {
  MountainLayer(this.labels, {this.naraOverview = true});
  final List<MountainLabel> labels;
  final bool naraOverview;
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
    Offset Function(math.Point<double>) project, {
    String prefectureId = '29',
  }) async {
    final json =
        jsonDecode(
              await loadCoastalAsset(
                prefectureId == '29'
                    ? 'assets/data/nara_mountains.json'
                    : 'assets/data/mountains/$prefectureId.json',
                version: 'mountains-20261017-v2',
              ),
            )
            as Map<String, dynamic>;
    return MountainLayer.fromJson(
      json,
      project,
      naraOverview: prefectureId == '29',
    );
  }

  factory MountainLayer.fromJson(
    Map<String, dynamic> json,
    Offset Function(math.Point<double>) project, {
    bool naraOverview = true,
  }) {
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
          overview: l['overview'] as bool?,
        ),
    ];
    int priority(MountainLabel label) {
      if (label.overview != null) {
        return label.overview! ? 0 : overviewNames.length;
      }
      final index = overviewNames.indexOf(label.name);
      return index < 0 ? overviewNames.length : index;
    }

    labels.sort((a, b) {
      final order = priority(a).compareTo(priority(b));
      return order == 0 ? a.name.compareTo(b.name) : order;
    });
    return MountainLayer(labels, naraOverview: naraOverview);
  }

  void paintLabels(
    Canvas canvas,
    Path clip,
    double zoom,
    List<Rect> occupied, {
    bool municipal = false,
    Rect? viewport,
  }) {
    final visible = viewport?.inflate(80 / zoom);
    final clipBounds = clip.getBounds();
    final needsClip = naraOverview || municipal;
    var candidates = 0;
    var displayed = 0;
    for (final label in labels) {
      if (zoom < 0.65 &&
          !(label.overview ?? overviewNames.contains(label.name))) {
        continue;
      }
      if (displayed >= 32) break;
      if (visible != null && !visible.contains(label.point)) continue;
      if (!clipBounds.contains(label.point)) continue;
      if (++candidates > 96) break;
      if (needsClip && !clip.contains(label.point)) continue;
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
      // Move only the text when another label occupies its anchor.
      for (final offset in [
        Offset.zero,
        Offset(0, -(text.height / 2 + 10 / zoom)),
        Offset(0, text.height / 2 + 10 / zoom),
        Offset(text.width / 2 + 10 / zoom, 0),
        Offset(-(text.width / 2 + 10 / zoom), 0),
      ]) {
        final center = label.point + offset;
        if (!clipBounds.contains(center)) continue;
        final rect = Rect.fromCenter(
          center: center,
          width: text.width + 8 / zoom,
          height: text.height + 4 / zoom,
        );
        if (occupied.any((r) => r.overlaps(rect))) continue;
        if ((needsClip || offset != Offset.zero) && !clip.contains(center)) {
          continue;
        }
        occupied.add(rect);
        displayed++;
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

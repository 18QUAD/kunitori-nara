import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/water.dart';

void main() {
  test(
    'water polygons preserve islands and use the supplied map projection',
    () {
      final layer = WaterLayer.fromJson({
        'lines': [
          [
            [1, 2],
            [3, 4],
          ],
        ],
        'areas': [
          [
            [
              [0, 0],
              [10, 0],
              [10, 10],
              [0, 10],
              [0, 0],
            ],
            [
              [4, 4],
              [6, 4],
              [6, 6],
              [4, 6],
              [4, 4],
            ],
          ],
        ],
        'labels': [
          {
            'name': '川',
            'point': [2, 3],
          },
        ],
      }, (p) => Offset(p.x * 2, 20 - p.y * 2));
      expect(layer.areas.contains(const Offset(2, 18)), isTrue);
      expect(layer.areas.contains(const Offset(10, 10)), isFalse);
      expect(layer.rivers.getBounds(), const Rect.fromLTRB(2, 12, 6, 16));
      expect(layer.labels.single.point, const Offset(4, 14));
    },
  );

  test('bundled GSI water includes major Nara rivers and reservoirs', () {
    final json =
        jsonDecode(File('assets/data/nara_water.json').readAsStringSync())
            as Map<String, dynamic>;
    final layer = WaterLayer.fromJson(json, (p) => Offset(p.x, p.y));
    expect(layer.rivers.getBounds().isEmpty, isFalse);
    final names = layer.labels.map((l) => l.name).toSet();
    expect(names, containsAll(['大和（初瀬）川', '吉野川', '十津川', '北山川', '池原貯水池']));
    final bounds = layer.areas.getBounds().expandToInclude(
      layer.rivers.getBounds(),
    );
    expect(bounds.left, greaterThan(135.53));
    expect(bounds.right, lessThan(136.24));
    expect(bounds.top, greaterThan(33.85));
    expect(bounds.bottom, lessThan(34.79));
  });
}

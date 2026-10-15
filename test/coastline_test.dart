import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/national_atlas.dart';

Path shape(Map<String, dynamic> json) {
  final pref = Prefecture.fromJson({
    ...json,
    'id': json['id'] ?? '',
    'name': json['name'] ?? '',
  });
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final polygon in pref.polygons) {
    for (final ring in polygon) {
      if (ring.isEmpty) continue;
      path.moveTo(ring.first.x, ring.first.y);
      for (final p in ring.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      path.close();
    }
  }
  return path;
}

void main() {
  test('Mikawa Bay is outside prefecture, city and town hit regions', () {
    const sea = Offset(137.25386138, 34.75205628);
    final national = jsonDecode(
      File('assets/data/japan.json').readAsStringSync(),
    );
    final aichi = (national['prefectures'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['id'] == '23');
    expect(shape(aichi).contains(sea), isFalse);
    final county = jsonDecode(
      File('assets/data/prefectures/23.json').readAsStringSync(),
    );
    expect(shape(county).contains(sea), isFalse);
    for (final row in [
      ...county['cities'] as List,
      ...county['towns'] as List,
    ]) {
      expect(shape(row).contains(sea), isFalse, reason: row['id']);
    }
    expect(shape(county).contains(const Offset(136.9066, 35.1815)), isTrue);
    expect(shape(county).contains(const Offset(136.805, 34.857)), isTrue);
  });

  test('inland lake and airport island remain inside prefecture regions', () {
    final shiga = jsonDecode(
      File('assets/data/prefectures/25.json').readAsStringSync(),
    );
    expect(shape(shiga).contains(const Offset(136.05, 35.25)), isTrue);
    final osaka = jsonDecode(
      File('assets/data/prefectures/27.json').readAsStringSync(),
    );
    expect(shape(osaka).contains(const Offset(135.243, 34.434)), isTrue);
    expect(shape(osaka).contains(const Offset(135.3, 34.5)), isFalse);
  });

  test('coast coordinates keep double precision', () {
    final pref = Prefecture.fromJson({
      'id': '23',
      'name': 'test',
      'polygons': [
        [
          [
            [136.123456789, 34.123456789],
            [136.2, 34.2],
            [136.1, 34.2],
            [136.123456789, 34.123456789],
          ],
        ],
      ],
    });
    expect(
      pref.polygons.single.single.first,
      const Point(136.123456789, 34.123456789),
    );
  });
}

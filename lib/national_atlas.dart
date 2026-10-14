import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'game.dart';

/// Population and adjacency are resident; detailed polygons are loaded by prefecture.
class NationalAtlas {
  NationalAtlas(this.atlas, this.prefectures);
  final Atlas atlas;
  final Map<String, Prefecture> prefectures;
  final Map<String, Future<void>> _loads = {};

  static Future<NationalAtlas> load() async {
    final nara =
        jsonDecode(await rootBundle.loadString('assets/data/nara.json'))
            as Map<String, dynamic>;
    final national =
        jsonDecode(await rootBundle.loadString('assets/data/japan.json'))
            as Map<String, dynamic>;
    if (national['censusYear'] != 2020 ||
        (national['prefectures'] as List).length != 47) {
      throw const FormatException('全国データの年次・都道府県数が不正です。');
    }
    final atlas = Atlas.fromJson({
      'cities': [...nara['cities'] as List, ...national['cities'] as List],
      'towns': [...nara['towns'] as List, ...national['towns'] as List],
    });
    for (final pair in national['crossPrefectureNeighbors'] as List) {
      final a = atlas.sourceToTown[pair[0]], b = atlas.sourceToTown[pair[1]];
      if (a == null || b == null) {
        throw const FormatException('県境の隣接地域が見つかりません。');
      }
      if (a != b) {
        atlas.towns[a]!.neighbors.add(b);
        atlas.towns[b]!.neighbors.add(a);
      }
    }
    return NationalAtlas(atlas, {
      for (final p in national['prefectures'] as List)
        p['id'] as String: Prefecture.fromJson(p as Map<String, dynamic>),
    });
  }

  Future<void> ensureGeometry(String prefecture) {
    if (prefecture == '29') return Future.value();
    return _loads.putIfAbsent(prefecture, () async {
      try {
        final data =
            jsonDecode(
                  await rootBundle.loadString(
                    'assets/data/prefectures/$prefecture.json',
                  ),
                )
                as Map<String, dynamic>;
        // Decode everything before changing the live atlas, so retry is safe.
        final decoded = <String, List<List<List<Point<double>>>>>{};
        for (final row in data['towns'] as List) {
          final source = row['id'] as String;
          final id = atlas.sourceToTown[source];
          if (id == null || !source.startsWith(prefecture)) {
            throw const FormatException('県の描画データが全国データと一致しません。');
          }
          final polygons =
              Town.fromJson({
                ...row as Map<String, dynamic>,
                'name': '',
                'cityId': source.substring(0, 5),
                'population': 0,
                'area': 0,
                'neighbors': <String>[],
              }).polygons;
          decoded.putIfAbsent(id, () => []).addAll(polygons);
        }
        for (final entry in decoded.entries) {
          atlas.towns[entry.key]!.polygons.addAll(entry.value);
        }
      } catch (_) {
        _loads.remove(prefecture);
        rethrow;
      }
    });
  }
}

class Prefecture {
  Prefecture.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      polygons =
          Town.fromJson({
            'id': j['id'],
            'name': j['name'],
            'cityId': '',
            'population': 0,
            'area': 0,
            'neighbors': <String>[],
            'polygons': j['polygons'],
          }).polygons;
  final String id, name;
  final List<List<List<Point<double>>>> polygons;
}

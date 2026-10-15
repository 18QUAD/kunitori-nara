import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'coastal_assets.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'game.dart';

/// Population and adjacency are resident; detailed polygons are loaded by prefecture.
class NationalAtlas {
  NationalAtlas(this.atlas, this.prefectures);
  final Atlas atlas;
  final Map<String, Prefecture> prefectures;
  String? _requested;
  Future<void>? _requestedLoad;
  static NationalAtlas? _cached;
  Future<void> _geometryTail = Future.value();
  String? _resident;
  String? get residentGeometry => _resident;

  Future<T> _serial<T>(FutureOr<T> Function() action) {
    final result = _geometryTail.then((_) => action());
    _geometryTail = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace st) {},
    );
    return result;
  }

  /// Convert what the national view needs while this prefecture is resident.
  /// The next prefecture can then replace its large coordinate lists safely.
  Future<void> withGeometry(String id, void Function() convert) {
    _requested = null;
    _requestedLoad = null;
    return _serial(() async {
      await _readGeometry(id);
      convert();
    });
  }

  void _releaseGeometry() {
    final old = _resident;
    if (old == null) return;
    for (final city in atlas.byCity.entries.where(
      (e) => e.key.startsWith(old),
    )) {
      for (final town in city.value) {
        town.polygons.clear();
      }
    }
    atlas.cityPolygons.removeWhere((id, _) => id.startsWith(old));
    atlas.prefecturePolygons.remove(old);
    _resident = null;
  }

  static Future<NationalAtlas> load() async {
    if (_cached != null) return _cached!;
    final nara =
        jsonDecode(
              await rootBundle.loadString(
                'assets/data/nara.json',
                cache: false,
              ),
            )
            as Map<String, dynamic>;
    final national =
        jsonDecode(await loadCoastalAsset('assets/data/japan.json'))
            as Map<String, dynamic>;
    if (national['censusYear'] != 2020 ||
        (national['prefectures'] as List).length != 47) {
      throw const FormatException('全国データの年次・都道府県数が不正です。');
    }
    final rows = <dynamic>[
      ...nara['towns'] as List,
      ...national['towns'] as List,
    ];
    (nara['towns'] as List).clear();
    (national['towns'] as List).clear();
    final atlas = Atlas.fromJson({
      'cities': [...nara['cities'] as List, ...national['cities'] as List],
      'towns': rows,
    }, consumeTownRows: true);
    for (final pair in [
      ...national['crossPrefectureNeighbors'] as List,
      ...national['crossMunicipalityNeighbors'] as List? ?? [],
    ]) {
      final a = atlas.sourceToTown[pair[0]], b = atlas.sourceToTown[pair[1]];
      if (a == null || b == null) {
        throw const FormatException('県境の隣接地域が見つかりません。');
      }
      if (a != b) {
        atlas.towns[a]!.neighbors.add(b);
        atlas.towns[b]!.neighbors.add(a);
      }
    }
    atlas.enableSeaTravel();
    // Migration needs source IDs and populations; gameplay uses the merged graph.
    // Drop the duplicate imported neighbor strings after constructing that graph.
    for (final source in atlas.sourceTowns.values) {
      if (!source.cityId.startsWith('29')) source.neighbors.clear();
    }
    return _cached = NationalAtlas(atlas, {
      for (final p in national['prefectures'] as List)
        p['id'] as String: Prefecture.fromJson(p as Map<String, dynamic>),
    });
  }

  Future<void> ensureGeometry(String prefecture) {
    if (prefecture == '29') return Future.value();
    if (_requested == prefecture && _requestedLoad != null) {
      return _requestedLoad!;
    }
    _requested = prefecture;
    final load = _serial(() => _readGeometry(prefecture));
    _requestedLoad = load;
    load.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (identical(_requestedLoad, load)) {
          _requested = null;
          _requestedLoad = null;
        }
      },
    );
    return load;
  }

  Future<void> _readGeometry(String prefecture) async {
    if (prefecture == '29' || _resident == prefecture) return;
    _releaseGeometry();

    try {
      final data =
          jsonDecode(
                await loadCoastalAsset(
                  'assets/data/prefectures/$prefecture.json',
                ),
              )
              as Map<String, dynamic>;
      // Decode everything before changing the live atlas, so retry is safe.
      final decoded = <String, List<List<List<Point<double>>>>>{};
      final rows = data['towns'] as List;
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index] as Map<String, dynamic>;
        final source = row['id'] as String;
        final id = atlas.sourceToTown[source];
        if (id == null || !source.startsWith(prefecture)) {
          throw const FormatException('県の描画データが全国データと一致しません。');
        }
        final polygons =
            Town.fromJson({
              ...row,
              'name': '',
              'cityId': source.substring(0, 5),
              'population': 0,
              'area': 0,
              'neighbors': <String>[],
            }).polygons;
        decoded.putIfAbsent(id, () => []).addAll(polygons);
        rows[index] = null;
      }
      final cityShapes = <String, List<List<List<Point<double>>>>>{};
      for (final row in data['cities'] as List? ?? []) {
        cityShapes[row['id'] as String] =
            Prefecture.fromJson(row as Map<String, dynamic>).polygons;
      }
      final outline =
          data['polygons'] == null
              ? null
              : Prefecture.fromJson({
                'id': prefecture,
                'name': '',
                'polygons': data['polygons'],
              }).polygons;
      for (final entry in decoded.entries) {
        atlas.towns[entry.key]!.polygons.addAll(entry.value);
      }
      atlas.cityPolygons.addAll(cityShapes);
      if (outline != null) atlas.prefecturePolygons[prefecture] = outline;
      _resident = prefecture;
    } catch (_) {
      rethrow;
    }
  }
}

// Coastlines contain many points. Store doubles in one buffer per ring instead
// of retaining a Dart Point object and list slot for every coastline vertex.
class _CoordinateRing extends ListBase<Point<double>> {
  _CoordinateRing(List<dynamic> json) : _xy = Float64List(json.length * 2) {
    for (var i = 0; i < json.length; i++) {
      _xy[i * 2] = (json[i][0] as num).toDouble();
      _xy[i * 2 + 1] = (json[i][1] as num).toDouble();
    }
  }
  final Float64List _xy;
  @override
  int get length => _xy.length ~/ 2;
  @override
  set length(int value) => throw UnsupportedError('Read-only geometry');
  @override
  Point<double> operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return Point(_xy[index * 2], _xy[index * 2 + 1]);
  }

  @override
  void operator []=(int index, Point<double> value) =>
      throw UnsupportedError('Read-only geometry');
}

class Prefecture {
  Prefecture.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      polygons = [
        for (final polygon in j['polygons'] as List)
          [for (final ring in polygon as List) _CoordinateRing(ring as List)],
      ];
  final String id, name;
  final List<List<List<Point<double>>>> polygons;
}

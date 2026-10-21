import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'coastal_assets.dart';
import 'prepared_territory.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/services.dart';
import 'game.dart';
import 'town_connections.dart';
import 'office_marker.dart';
import 'national_tips.dart';
import 'diagnostics.dart';

/// Population and adjacency are resident; detailed polygons are loaded by prefecture.
class NationalAtlas {
  NationalAtlas(this.atlas, this.prefectures, {this.tips});
  final NationalTips? tips;
  final Atlas atlas;
  final Map<String, Prefecture> prefectures;
  String? _requested;
  Future<void>? _requestedLoad;
  static NationalAtlas? _cached;
  Future<void>? _geometryTail;
  String? _resident;
  String? get residentGeometry => _resident;

  Future<T> _serial<T>(FutureOr<T> Function() action) {
    final previous = _geometryTail;
    final result =
        previous == null
            ? Future<T>.sync(action)
            : previous.then((_) => action());
    late final Future<void> tail;
    void finish() {
      if (identical(_geometryTail, tail)) _geometryTail = null;
    }

    tail = result.then<void>(
      (_) => finish(),
      onError: (Object e, StackTrace st) => finish(),
    );
    _geometryTail = tail;
    return result;
  }

  /// Convert what the national view needs while this prefecture is resident.
  /// The next prefecture can then replace its large coordinate lists safely.
  Future<void> withGeometry(String id, void Function() convert) {
    _requested = null;
    _requestedLoad = null;
    return _serial(() async {
      try {
        await _readGeometry(id);
        convert();
      } finally {
        _releaseGeometry();
      }
    });
  }

  /// No detailed map is visible. Serialized with loads so old requests cannot
  /// clear the next prefecture while its map is being built.
  Future<void> releaseGeometry() {
    _requested = null;
    _requestedLoad = null;
    return _serial(_releaseGeometry);
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
    atlas.preparedGeometryPrefectures.remove(old);
    _resident = null;
  }

  static Future<NationalAtlas> load() async {
    if (_cached != null) return _cached!;
    final nara =
        jsonDecode(
              await rootBundle.loadString(
                'assets/data/nara_metadata.json',
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
    final officeData =
        jsonDecode(
              await rootBundle.loadString(
                'assets/data/japan_offices.json',
                cache: false,
              ),
            )
            as Map<String, dynamic>;
    for (final row in officeData['offices'] as List) {
      final id = row['id'] as String;
      final city = row['cityId'] as String;
      final source = row['sourceTownId'] as String?;
      final town = source == null ? null : atlas.sourceToTown[source];
      if (!atlas.cities.containsKey(city) ||
          city.startsWith('29') ||
          atlas.mapOffices.containsKey(id) ||
          (source != null &&
              (town == null || atlas.towns[town]!.cityId != city))) {
        throw const FormatException('役所マークの自治体・町が全国データと一致しません。');
      }
      atlas.mapOffices[id] = OfficeMarker(
        id: id,
        cityId: city,
        name: row['name'] as String,
        address: row['address'] as String,
        point: Point(
          (row['point'][0] as num).toDouble(),
          (row['point'][1] as num).toDouble(),
        ),
        isCity: row['isCity'] as bool,
        townId: town,
      );
    }
    if (atlas.cities.keys.any((city) => !atlas.mapOffices.containsKey(city))) {
      throw const FormatException('役所マークのない自治体があります。');
    }
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
    atlas.enableSeaTravel(seaTownConnections);
    // Migration needs source IDs and populations; gameplay uses the merged graph.
    // Drop the duplicate imported neighbor strings after constructing that graph.
    for (final source in atlas.sourceTowns.values) {
      if (!source.cityId.startsWith('29')) source.neighbors.clear();
    }
    return _cached = NationalAtlas(atlas, {
      for (final p in national['prefectures'] as List)
        p['id'] as String: Prefecture.fromJson(p as Map<String, dynamic>),
    }, tips: await NationalTips.load(atlas));
  }

  Future<void> ensureGeometry(String prefecture) {
    if (_geometryTail == null && _resident == prefecture) {
      return SynchronousFuture<void>(null);
    }
    if (_requested == prefecture && _requestedLoad != null) {
      return _requestedLoad!;
    }
    _requested = prefecture;
    final load = _serial(() async {
      var attempt = 0;
      while (true) {
        try {
          await _readGeometry(prefecture);
          return;
        } catch (_) {
          attempt++;
          await Future<void>.delayed(Duration(seconds: min(10, attempt)));
        }
      }
    });
    _requestedLoad = load;
    load.then<void>(
      (_) {
        if (identical(_requestedLoad, load)) _requestedLoad = null;
      },
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
    if (_resident == prefecture) return;
    _releaseGeometry();

    recordDiagnostic('geometry_load_start', {
      'destinationPrefecture': prefecture,
    });
    try {
      final prepared = await PreparedTerritory.load(prefecture);
      final decoded = <String, List<List<List<Point<double>>>>>{};
      for (final town in atlas.towns.values.where(
        (t) => t.id.startsWith(prefecture),
      )) {
        decoded[town.id] = prepared.polygons(town.id);
      }
      final cityShapes = <String, List<List<List<Point<double>>>>>{};
      for (final city in atlas.cities.keys.where(
        (id) => id.startsWith(prefecture),
      )) {
        cityShapes[city] = prepared.polygons(city);
      }
      final outline = prepared.polygons('pref');
      for (final entry in decoded.entries) {
        atlas.towns[entry.key]!.polygons.addAll(entry.value);
      }
      atlas.cityPolygons.addAll(cityShapes);
      atlas.prefecturePolygons[prefecture] = outline;
      atlas.preparedGeometryPrefectures.add(prefecture);
      _resident = prefecture;
      recordDiagnostic('geometry_load_done', {
        'destinationPrefecture': prefecture,
        'geometryPrepared': true,
      });
    } catch (error) {
      recordDiagnostic('geometry_load_error', {
        'destinationPrefecture': prefecture,
        'error': error.toString(),
      });
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

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
import 'nearest_connections.dart';
import 'office_marker.dart';
import 'national_tips.dart';
import 'national_conquest.dart';
import 'compact_towns.dart';

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
    atlas.pinMetadata(null);
  }

  static Future<NationalAtlas> load() async {
    if (_cached != null) return _cached!;
    final data =
        jsonDecode(
              await rootBundle.loadString(
                'assets/data/compact/index.json',
                cache: false,
              ),
            )
            as Map<String, dynamic>;
    if (data['schema'] != 1)
      throw const FormatException('Invalid national index');
    final coast = await rootBundle.load('assets/data/compact/coast.bin');
    var offset = 0;
    int count() {
      final v = coast.getUint32(offset, Endian.little);
      offset += 4;
      return v;
    }

    final prefectures = <String, Prefecture>{};
    for (final p in data['prefectures'] as List) {
      final polygons = <List<List<Point<double>>>>[];
      final np = count();
      for (var i = 0; i < np; i++) {
        final rings = <List<Point<double>>>[];
        final nr = count();
        for (var j = 0; j < nr; j++) {
          final n = count();
          final xy = Float64List(n * 2);
          for (var k = 0; k < n * 2; k++) {
            xy[k] = coast.getFloat64(offset, Endian.little);
            offset += 8;
          }
          rings.add(_CoordinateRing.fromBuffer(xy));
        }
        polygons.add(rings);
      }
      prefectures[p['id']] = Prefecture.prepared(p['id'], p['name'], polygons);
    }
    final index = CompactTowns.empty();
    for (final path in data['townFiles']) {
      index.addRows(
        jsonDecode(
              await rootBundle.loadString(
                'assets/data/compact/$path',
                cache: false,
              ),
            )
            as List,
      );
    }
    index.finish();
    final atlas = Atlas.fromPrepared(data, preparedTowns: index);
    final offices = jsonDecode(
      await rootBundle.loadString(
        'assets/data/japan_offices.json',
        cache: false,
      ),
    );
    final sourceIds = <String, String>{};
    for (final row in offices['offices']) {
      final city = row['cityId'] as String;
      final source = row['sourceTownId'] as String?;
      if (row['id'] == city && source != null) sourceIds[city] = source;
      atlas.mapOffices[row['id']] = OfficeMarker(
        id: row['id'],
        cityId: city,
        name: row['name'],
        address: row['address'],
        point: Point(
          (row['point'][0] as num).toDouble(),
          (row['point'][1] as num).toDouble(),
        ),
        isCity: row['isCity'],
        townId: source == null ? null : atlas.sourceToTown[source],
      );
    }
    enableNationalConquest(atlas, {
      for (final p in prefectures.values) p.id: p.name,
    }, officeSourceTownIds: sourceIds);
    atlas.enableSeaTravel(seaTownConnections);
    atlas.enableNearbyTravel(nearestTownConnections);
    return _cached = NationalAtlas(
      atlas,
      prefectures,
      tips: await NationalTips.load(atlas),
    );
  }

  Future<void> prepareLegacySave(Map<String, dynamic>? save) async {
    if (save == null || save['territoryUnit'] == 'town-v1') return;
    final ids = <String>{
      ...((save['owned'] as List?) ?? []).cast<String>(),
      ...((save['everOwned'] as List?) ?? []).cast<String>(),
      ...((save['progress'] as Map?) ?? {}).keys.cast<String>(),
      if (save['home'] is String) save['home'] as String,
    };
    for (final pref in ids.map((id) => id.substring(0, 2)).toSet()) {
      final rows =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/compact/legacy/$pref.json',
                  cache: false,
                ),
              )
              as List;
      for (final row in rows) {
        final id = row[0] as String, target = row[1] as String;
        final town = Town.fromJson({
          'id': id,
          'name': '',
          'cityId': id.substring(0, 5),
          'population': row[2],
          'area': 0,
          'neighbors': const [],
          'polygons': const [],
        });
        atlas.sourceTowns[id] = town;
        atlas.sourceToTown[id] = target;
        atlas.membersByTown.putIfAbsent(target, () => []).add(town);
      }
    }
  }

  void releaseLegacySave() {
    atlas.sourceTowns.clear();
    atlas.membersByTown.clear();
    // Keep the tiny office aliases, discarding only migration-only IDs.
    final aliases = atlas.sourceToTown;
    final keep = <String>{...atlas.offices.values.map((o) => o.sourceTownId)};
    // CompactAliases identity lookups do not allocate national alias entries.
    if (aliases is CompactAliases)
      aliases.aliases.removeWhere((id, _) => !keep.contains(id));
  }

  static Future<NationalAtlas> loadUnpackedForBuild() async {
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
    enableNationalConquest(
      atlas,
      {
        for (final p in national['prefectures'] as List)
          p['id'] as String: p['name'] as String,
      },
      officeSourceTownIds: {
        for (final row in officeData['offices'] as List)
          if (row['id'] == row['cityId'] && row['sourceTownId'] != null)
            row['cityId'] as String: row['sourceTownId'] as String,
      },
    );
    atlas.enableSeaTravel(seaTownConnections);
    atlas.enableNearbyTravel(nearestTownConnections);
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
    atlas.pinMetadata(prefecture);

    try {
      final prepared = await PreparedTerritory.load(prefecture);
      final decoded = <String, List<List<List<Point<double>>>>>{};
      for (final town in atlas.byCity.entries
          .where((e) => e.key.startsWith(prefecture))
          .expand((e) => e.value)) {
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
    } catch (error) {
      rethrow;
    }
  }
}

// Coastlines contain many points. Store doubles in one buffer per ring instead
// of retaining a Dart Point object and list slot for every coastline vertex.
class _CoordinateRing extends ListBase<Point<double>> {
  _CoordinateRing.fromBuffer(this._xy);
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
  Prefecture.prepared(this.id, this.name, this.polygons);
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

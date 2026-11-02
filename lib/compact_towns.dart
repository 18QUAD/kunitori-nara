import 'dart:collection';
import 'dart:typed_data';
import 'game.dart';

/// National metadata uses packed numeric arrays. Full Town objects are created
/// only when used; the visible prefecture is pinned while its geometry is live.
class CompactTowns extends MapBase<String, Town> {
  CompactTowns(List<dynamic> rows) {
    addRows(rows);
    finish();
  }
  CompactTowns.empty();
  final _population = <int>[], _offsets = <int>[], _links = <int>[];
  final _area = <double>[];
  void addRows(List<dynamic> rows) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i] as List;
      final id = row[0] as String;
      positions[id] = ids.length;
      ids.add(id);
      names.add(row[1] as String);
      _population.add(row[2] as int);
      _area.add((row[3] as num).toDouble());
      _offsets.add(_links.length);
      _links.addAll((row[4] as List).cast<int>());
      rows[i] = null;
    }
    rows.clear();
  }

  void finish() {
    population = Uint32List.fromList(_population);
    area = Float64List.fromList(_area);
    offsets = Uint32List.fromList([..._offsets, _links.length]);
    neighbors = Uint32List.fromList(_links);
    _population.clear();
    _area.clear();
    _offsets.clear();
    _links.clear();
  }

  final ids = <String>[], names = <String>[];
  final positions = <String, int>{};
  late final Uint32List population, offsets, neighbors;
  late final Float64List area;
  final _resident = <String, Town>{}, _recent = <String, Town>{};
  String? _prefecture;
  int get materializedCount => _resident.length + _recent.length;
  void pinPrefecture(String? value) {
    if (value == _prefecture) return;
    _resident.clear();
    _recent.clear();
    _prefecture = value;
  }

  @override
  Town? operator [](Object? key) {
    final i = positions[key];
    if (i == null) return null;
    final id = ids[i];
    final pinned = id.startsWith(_prefecture ?? '!');
    final cache = pinned ? _resident : _recent;
    final hit = cache.remove(id);
    if (hit != null) {
      cache[id] = hit;
      return hit;
    }
    final town = Town.fromJson({
      'id': id,
      'name': names[i],
      'cityId': id.substring(0, 5),
      'population': population[i],
      'area': area[i],
      'polygons': const [],
      'neighbors': [
        for (var n = offsets[i]; n < offsets[i + 1]; n++) ids[neighbors[n]],
      ],
    });
    cache[id] = town;
    if (!pinned && cache.length > 512) cache.remove(cache.keys.first);
    return town;
  }

  @override
  bool containsKey(Object? key) => positions.containsKey(key);
  @override
  Iterable<String> get keys => ids;
  @override
  int get length => ids.length;
  @override
  void operator []=(String key, Town value) =>
      throw UnsupportedError('Immutable index');
  @override
  Town? remove(Object? key) => throw UnsupportedError('Immutable index');
  @override
  void clear() => throw UnsupportedError('Immutable index');
}

class CompactTownList extends ListBase<Town> {
  CompactTownList(this.towns, Iterable<int> indices)
    : indices = Uint32List.fromList(indices.toList());
  final CompactTowns towns;
  final Uint32List indices;
  @override
  int get length => indices.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable index');
  @override
  Town operator [](int index) => towns[towns.ids[indices[index]]]!;
  @override
  void operator []=(int index, Town value) =>
      throw UnsupportedError('Immutable index');
}

class CompactAliases extends MapBase<String, String> {
  CompactAliases(this.towns, Map<String, dynamic> aliases)
    : aliases = Map<String, String>.from(aliases);
  final CompactTowns towns;
  final Map<String, String> aliases;
  @override
  String? operator [](Object? key) =>
      aliases[key] ?? (towns.containsKey(key) ? key as String : null);
  @override
  Iterable<String> get keys => {...towns.keys, ...aliases.keys};
  @override
  void operator []=(String key, String value) {
    aliases[key] = value;
  }

  @override
  String? remove(Object? key) => aliases.remove(key);
  @override
  void clear() => aliases.clear();
}

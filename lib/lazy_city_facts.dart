import 'dart:collection';
import 'game.dart';

/// National quiz text is generated on access, with a small bounded cache.
/// Nara's existing culture catalogue remains available for save validation.
class LazyCityFacts extends MapBase<String, List<LocalFact>> {
  LazyCityFacts(Map<String, List<LocalFact>> initial) {
    _pinned.addAll(
      Map.fromEntries(initial.entries.where((e) => e.key.startsWith('29'))),
    );
  }
  final _pinned = <String, List<LocalFact>>{},
      _cache = <String, List<LocalFact>>{};
  final _factories = <String, List<LocalFact> Function()>{};
  String? _prefecture;
  void register(String city, List<LocalFact> Function() factory) {
    _factories[city] = factory;
  }

  void pin(String? prefecture) {
    _prefecture = prefecture;
    for (final key
        in _pinned.keys
            .where(
              (k) => !k.startsWith('29') && !k.startsWith(prefecture ?? '!'),
            )
            .toList())
      _pinned.remove(key);
  }

  @override
  List<LocalFact>? operator [](Object? key) {
    final hit = _pinned[key] ?? _cache.remove(key);
    if (hit != null) {
      if (!_pinned.containsKey(key)) _cache[key as String] = hit;
      return hit;
    }
    final factory = _factories[key];
    if (factory == null) return null;
    final value = factory();
    this[key as String] = value;
    return value;
  }

  @override
  void operator []=(String key, List<LocalFact> value) {
    if (key.startsWith('29') || key.startsWith(_prefecture ?? '!')) {
      _pinned[key] = value;
      return;
    }
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > 32) _cache.remove(_cache.keys.first);
  }

  @override
  Iterable<String> get keys => {..._pinned.keys, ..._factories.keys};
  @override
  List<LocalFact>? remove(Object? key) =>
      _pinned.remove(key) ?? _cache.remove(key);
  @override
  void clear() {
    _pinned.clear();
    _cache.clear();
    _factories.clear();
  }

  @override
  bool containsKey(Object? key) =>
      _pinned.containsKey(key) || _factories.containsKey(key);
  Iterable<String> get knownIds sync* {
    for (final fs in _pinned.entries.where((e) => e.key.startsWith('29')))
      yield* fs.value.map((f) => f.id);
    for (final city in _factories.keys)
      for (final kind in [
        'count',
        'population',
        'largest',
        'prefecture',
        'office',
      ])
        yield '$city:conquest:$kind';
  }
}

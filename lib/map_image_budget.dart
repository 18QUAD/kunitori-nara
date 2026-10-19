import 'package:flutter/foundation.dart';

/// One retained-image budget across the worker and Flutter. Decoder workspaces,
/// live geometry, engine resources and the rest of the application are separate.
enum MapImageKind { source, background, boundary }

class MapImageBudget extends ChangeNotifier {
  static final shared = MapImageBudget();
  static const mib = 1024 * 1024;
  int megabytes = 32;
  final _entries = <Object, (MapImageKind, int)>{};
  int get totalBytes => megabytes * mib;
  int get compressedBytes => totalBytes ~/ 8;
  int limit(MapImageKind kind) => switch (kind) {
    MapImageKind.source => totalBytes * 5 ~/ 16,
    MapImageKind.background || MapImageKind.boundary => totalBytes * 9 ~/ 32,
  };
  int used(MapImageKind kind) => _entries.values
      .where((entry) => entry.$1 == kind)
      .fold(0, (total, entry) => total + entry.$2);
  int get retainedBytes => _entries.values.fold(0, (n, entry) => n + entry.$2);
  int rasterCells(MapImageKind kind) =>
      (limit(kind) ~/ mib).clamp(1, kind == MapImageKind.background ? 12 : 24);

  void configure(int value) {
    if (![32, 64, 128, 256].contains(value)) {
      throw ArgumentError.value(value, 'megabytes');
    }
    if (megabytes == value) return;
    megabytes = value;
    notifyListeners();
  }

  bool reserve(Object key, MapImageKind kind, int bytes) {
    if (_entries.containsKey(key)) {
      throw StateError('Duplicate image reservation');
    }
    if (bytes < 0 || used(kind) + bytes > limit(kind)) return false;
    _entries[key] = (kind, bytes);
    return true;
  }

  void release(Object? key) => _entries.remove(key);
  Map<String, Object> get diagnosticCounts => {
    'limitBytes': totalBytes,
    'compressedLimitBytes': compressedBytes,
    'sourceBytes': used(MapImageKind.source),
    'backgroundBytes': used(MapImageKind.background),
    'boundaryBytes': used(MapImageKind.boundary),
    'retainedImageBytes': retainedBytes,
  };
}

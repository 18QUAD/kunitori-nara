import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'game.dart';
import 'map_view.dart';

/// Serial writes, coalescing quick taps while a previous write is in flight.
/// A failed write remains retryable and never displays a false "saved" status.
class SaveStore {
  SaveStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'kunitori.nara.v1';
  static const mapViewKey = 'kunitori.nara.mapView.v1';
  final Map<String, String> _pending = {};
  Future<void>? _writing;
  String? error;
  void Function()? onChanged;
  bool get saving => _writing != null;
  Game load(Atlas atlas) {
    final raw = preferences.getString(key);
    return raw == null
        ? Game(atlas)
        : Game.restore(atlas, jsonDecode(raw) as Map<String, dynamic>);
  }

  MapViewState? loadMapView(Atlas atlas) {
    try {
      final raw = preferences.getString(mapViewKey);
      return raw == null
          ? null
          : MapViewState.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
            atlas,
          );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMapView(MapViewState view) =>
      _saveValue(mapViewKey, jsonEncode(view.toJson()));
  Future<void> save(Game game) => _saveValue(key, jsonEncode(game.toJson()));

  Future<void> _saveValue(String storageKey, String value) {
    _pending[storageKey] = value;
    if (_writing != null) return _writing!;
    final future = _drain();
    _writing = future;
    return future.whenComplete(() {
      _writing = null;
      onChanged?.call();
    });
  }

  Future<void> _drain() async {
    error = null;
    while (_pending.isNotEmpty) {
      final storageKey = _pending.keys.first;
      final value = _pending.remove(storageKey)!;
      try {
        if (!await preferences.setString(storageKey, value)) {
          throw StateError('書き込み失敗');
        }
      } catch (_) {
        _pending.putIfAbsent(storageKey, () => value);
        error = '保存できませんでした。空き容量を確認して再試行してください。';
        break;
      }
    }
  }
}

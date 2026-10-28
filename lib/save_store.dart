import 'dart:convert';
import 'dart:async';
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
  bool _notifyAfterWrite = false;
  String? error;
  void Function()? onChanged;
  Timer? _saveTimer;
  Game? _queuedGame;

  Completer<void>? _queuedCompletion;
  bool get saving => _writing != null || _queuedGame != null;

  Future<void> queueSave(Game game) {
    _queuedGame = game;

    _queuedCompletion ??= Completer<void>();
    // A fixed maximum delay, not a debounce that can starve during a long burst.
    _saveTimer ??= Timer(const Duration(milliseconds: 200), () {
      unawaited(flush());
    });
    return _queuedCompletion!.future;
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final game = _queuedGame;
    if (game == null) return _writing ?? Future<void>.value();
    return save(game);
  }

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

  Future<void> save(Game game) {
    _saveTimer?.cancel();
    _saveTimer = null;
    _queuedGame = null;

    final completion = _queuedCompletion;
    _queuedCompletion = null;

    try {
      final value = jsonEncode(game.toJson());

      final result = _saveValue(key, value);
      if (completion != null) {
        result.then(completion.complete, onError: completion.completeError);
      }
      return result;
    } catch (error, stack) {
      completion?.completeError(error, stack);

      rethrow;
    }
  }

  Future<void> _saveValue(String storageKey, String value) {
    _notifyAfterWrite |= error != null;

    _pending[storageKey] = value;
    if (_writing != null) return _writing!;
    final future = _drain();
    _writing = future;
    return future.whenComplete(() {
      _writing = null;
      final notify = _notifyAfterWrite;
      _notifyAfterWrite = false;
      // Camera saves do not change game UI. Rebuilding it on every pan frame
      // creates a save -> full rebuild -> paint loop. Errors still notify.
      if (notify) onChanged?.call();
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
      } catch (failure, stack) {
        _notifyAfterWrite = true;

        _pending.putIfAbsent(storageKey, () => value);
        error = '保存できませんでした。空き容量を確認して再試行してください。';
        break;
      }
    }
  }
}

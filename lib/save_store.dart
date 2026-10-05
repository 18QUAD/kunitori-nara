import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'game.dart';

/// Serial writes, coalescing quick taps while a previous write is in flight.
/// A failed write remains retryable and never displays a false "saved" status.
class SaveStore {
  SaveStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'kunitori.nara.v1';
  String? _pending;
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

  Future<void> save(Game game) {
    _pending = jsonEncode(game.toJson());
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
    while (_pending != null) {
      final value = _pending!;
      _pending = null;
      try {
        if (!await preferences.setString(key, value)) {
          throw StateError('書き込み失敗');
        }
      } catch (_) {
        _pending ??= value;
        error = '保存できませんでした。空き容量を確認して再試行してください。';
        break;
      }
    }
  }
}

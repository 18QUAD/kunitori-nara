import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'save_store.dart';
import 'tip_appearance.dart';

/// Portable saves contain progress and preferences, never image cache contents.
class SaveTransfer {
  static const backupKey = 'kunitori.transfer.backup.v1';
  static const keys = [
    SaveStore.key,
    SaveStore.mapViewKey,
    TipAppearanceStore.key,
  ];
  static const maxLength = 16 * 1024 * 1024;

  static Map<String, String?> snapshot(SharedPreferences prefs) => {
    for (final key in keys) key: prefs.getString(key),
  };

  static String encode(Map<String, String?> values) {
    final bytes = utf8.encode(jsonEncode({'version': 1, 'values': values}));
    if (bytes.length > maxLength ~/ 2)
      throw const FormatException('データが大きすぎます。');
    return 'KNTR1.${base64Url.encode(bytes)}.${sha256.convert(bytes)}';
  }

  static Map<String, String?> decode(String input) {
    if (input.length > maxLength) throw const FormatException('データが大きすぎます。');
    final parts = input.replaceAll(RegExp(r'\s'), '').split('.');
    if (parts.length != 3 || parts[0] != 'KNTR1') {
      throw const FormatException('引き継ぎコードの形式が違います。');
    }
    final bytes = base64Url.decode(parts[1]);
    if (bytes.length > maxLength ~/ 2 ||
        sha256.convert(bytes).toString() != parts[2]) {
      throw const FormatException('コードが欠けているか、変更されています。');
    }
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('未対応の保存形式です。');
    final values = data['values'] as Map<String, dynamic>;
    final result = <String, String?>{};
    for (final key in keys) {
      final value = values[key];
      if (value != null && value is! String)
        throw const FormatException('保存形式が不正です。');
      if (value != null) jsonDecode(value as String);
      result[key] = value as String?;
    }
    if (result[SaveStore.key] == null)
      throw const FormatException('進行データがありません。');
    return result;
  }

  /// Caller validates Game.restore before writing. Backup is durable first.
  static Future<void> install(
    SharedPreferences prefs,
    Map<String, String?> values,
  ) async {
    final previous = snapshot(prefs);
    if (!await prefs.setString(backupKey, encode(previous))) {
      throw StateError('取り込み前のバックアップを保存できませんでした。');
    }
    try {
      for (final key in keys) {
        final value = values[key];
        final ok =
            value == null
                ? await prefs.remove(key)
                : await prefs.setString(key, value);
        if (!ok) throw StateError('保存できませんでした。');
      }
    } catch (_) {
      for (final key in keys) {
        final value = previous[key];
        if (value == null) {
          await prefs.remove(key);
        } else {
          await prefs.setString(key, value);
        }
      }
      rethrow;
    }
  }
}

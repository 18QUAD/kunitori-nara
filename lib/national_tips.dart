import 'dart:convert';
import 'package:flutter/services.dart';
import 'game.dart';

/// Keeps short text for one prefecture. The small ID catalogue stays resident
/// so restoring reading history does not require decoding all prefectures.
class NationalTips {
  NationalTips._(this.atlas, this.tipCount, this._bundle);
  final AssetBundle _bundle;
  final Atlas atlas;
  final int tipCount;
  String? residentPrefecture;
  String? _requested;
  Future<bool>? _pending;
  int _revision = 0;
  final _fallbacks = <String, List<LocalFact>>{};

  static Future<NationalTips> load(Atlas atlas, {AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final index =
        jsonDecode(
              await assets.loadString(
                'assets/data/tips/index.json',
                cache: false,
              ),
            )
            as Map<String, dynamic>;
    for (final id in (index['knownIds'] as List).cast<String>()) {
      if (!RegExp(r'^\d{5}:national:[0-9a-f]{12}$').hasMatch(id) ||
          id.startsWith('29') ||
          !atlas.cities.containsKey(id.substring(0, 5))) {
        throw const FormatException('地域tipsの履歴IDが自治体と一致しません。');
      }
      atlas.additionalFactIds.add(id);
    }
    // Earlier versions stored these IDs in reading history. Keep them valid
    // even while real text temporarily replaces their placeholder facts.
    for (final entry in atlas.facts.entries.where(
      (e) => !e.key.startsWith('29'),
    )) {
      atlas.additionalFactIds.addAll(entry.value.map((f) => f.id));
    }
    return NationalTips._(atlas, index['tips'] as int, assets);
  }

  void _release() {
    atlas.facts.addAll(_fallbacks);
    _fallbacks.clear();
    residentPrefecture = null;
  }

  Future<bool> ensure(String? prefecture) {
    final target = prefecture == '29' ? null : prefecture;
    if (_requested == target && _pending != null) return _pending!;
    if (_pending == null && residentPrefecture == target) {
      return Future.value(false);
    }
    _requested = target;
    final token = ++_revision;
    _release();
    if (target == null) {
      _pending = null;
      return Future.value(true);
    }
    late final Future<bool> work;
    work = _read(target, token).whenComplete(() {
      if (identical(_pending, work)) _pending = null;
    });
    _pending = work;
    return work;
  }

  Future<bool> _read(String prefecture, int token) async {
    final json =
        jsonDecode(
              await _bundle.loadString(
                'assets/data/tips/$prefecture.json',
                cache: false,
              ),
            )
            as Map<String, dynamic>;
    if (token != _revision) return false;
    final cities = json['cities'] as Map<String, dynamic>;
    final expected =
        atlas.cities.keys.where((id) => id.startsWith(prefecture)).toSet();
    if (prefecture == '29' ||
        json['prefectureId'] != prefecture ||
        cities.length != expected.length ||
        !expected.containsAll(cities.keys)) {
      throw const FormatException('地域tipsの都道府県・市区町村が不正です。');
    }
    final decoded = <String, List<LocalFact>>{};
    for (final entry in cities.entries) {
      decoded[entry.key] = [
        for (final row in entry.value as List)
          LocalFact(
            row['id'] as String,
            entry.key,
            row['category'] as String,
            row['text'] as String,
            '',
            '',
            const [],
            row['source'] as String,
            quizEligible: false,
          ),
      ];
      if (decoded[entry.key]!.isEmpty ||
          decoded[entry.key]!.any(
            (f) =>
                !atlas.additionalFactIds.contains(f.id) ||
                !f.id.startsWith('${entry.key}:') ||
                f.text.runes.length > 40 ||
                f.text.contains('人口') ||
                RegExp(
                  r'https?://|www\.|出典|脚注|Wikipedia|ウィキペディア|\[\d+\]|要出典|参考',
                ).hasMatch(f.text),
          )) {
        throw const FormatException('地域tipsの本文・IDが不正です。');
      }
    }
    if (token != _revision) return false;
    // Quiz questions stay resident while display-only culture tips are swapped.
    for (final city in decoded.keys) {
      decoded[city]!.addAll(atlas.facts[city]!.where((f) => f.quizEligible));
    }
    for (final city in decoded.keys) {
      _fallbacks[city] = atlas.facts[city]!;
    }
    atlas.facts.addAll(decoded);
    residentPrefecture = prefecture;
    return true;
  }
}

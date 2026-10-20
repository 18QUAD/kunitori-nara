import 'dart:collection';
import 'dart:typed_data';

/// Exact membership for the nationwide image pyramid without retaining one
/// String and one hash-table slot per tile. Coordinates are losslessly packed
/// into 30 bits; filenames are materialized only for tiles actually requested.
class PackedTileKeys extends IterableBase<String> {
  PackedTileKeys(Iterable<String> keys) {
    _codes = Uint32List(keys.length);
    var i = 0;
    for (final key in keys) {
      final code = encode(key);
      if (code == null) throw FormatException('Invalid prepared tile key', key);
      _codes[i++] = code;
    }
    _codes.sort();
    for (var i = 1; i < _codes.length; i++) {
      if (_codes[i] == _codes[i - 1]) {
        throw const FormatException('Duplicate prepared tile key');
      }
    }
  }

  static const layers = ['background', 'city', 'overview', 'pref', 'town'];
  static final _pattern = RegExp(
    r'^(-[1-3]|[0-8])_(0|[1-9]\d*)_(0|[1-9]\d*)_(background|city|overview|pref|town)$',
  );
  late final Uint32List _codes;
  int get storageBytes => _codes.lengthInBytes;
  @override
  int get length => _codes.length;

  static int? encode(String key) {
    final match = _pattern.firstMatch(key);
    if (match == null) return null;
    final level = int.parse(match[1]!);
    final x = int.parse(match[2]!), y = int.parse(match[3]!);
    if (x >= 4096 || y >= 2048) return null;
    return (level + 3) * 67108864 +
        x * 16384 +
        y * 8 +
        layers.indexOf(match[4]!);
  }

  static String decode(int code) =>
      '${(code ~/ 67108864) - 3}_${(code ~/ 16384) % 4096}_${(code ~/ 8) % 2048}_${layers[code % 8]}';

  @override
  bool contains(Object? element) {
    final code = element is String ? encode(element) : null;
    if (code == null) return false;
    var low = 0, high = _codes.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_codes[mid] < code) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < _codes.length && _codes[low] == code;
  }

  @override
  Iterator<String> get iterator => _codes.map(decode).iterator;
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/packed_tile_keys.dart';

void main() {
  test('all nationwide tile filenames have an exact four-byte identity', () {
    final json = jsonDecode(
      File('assets/data/map_images/index.json').readAsStringSync(),
    );
    final original = (json['tiles'] as Map).keys.cast<String>().toSet();
    final keys = PackedTileKeys(original);
    expect(keys.length, original.length);
    expect(keys.storageBytes, original.length * 4);
    final decoded = keys.toSet();
    expect(decoded.length, original.length);
    expect(decoded.containsAll(original), isTrue);
    for (final key in original) {
      if (!keys.contains(key) ||
          PackedTileKeys.decode(PackedTileKeys.encode(key)!) != key) {
        fail('Tile identity mismatch: $key');
      }
    }
    for (final key in [
      '9_0_0_town',
      '-4_0_0_pref',
      '8_4096_0_town',
      '8_0_2048_town',
      '8_0_0_unknown',
      '8_00_0_town',
      '8_-1_0_town',
      '8_0_0_town.webp',
    ]) {
      expect(keys.contains(key), isFalse, reason: key);
    }
    expect(keys.contains(null), isFalse);
    expect(PackedTileKeys(['8_4095_2047_town', '-3_0_0_background']).toSet(), {
      '8_4095_2047_town',
      '-3_0_0_background',
    });
  });
  test(
    'invalid or duplicate identities cannot silently alias a different tile',
    () {
      expect(() => PackedTileKeys(['8_4096_0_town']), throwsFormatException);
      expect(
        () => PackedTileKeys(['0_0_0_town', '0_0_0_town']),
        throwsFormatException,
      );
    },
  );
}

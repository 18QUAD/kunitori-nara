import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';
import 'prepared_territory_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a failed prefecture read recovers without a manual retry or duplicate polygons',
    () async {
      final town = {
        'id': '242080001',
        'cityId': '24208',
        'name': '検証町',
        'population': 1,
        'area': 1,
        'neighbors': <String>[],
        'polygons': <dynamic>[],
      };
      final nara =
          jsonDecode(File('assets/data/nara.json').readAsStringSync())
              as Map<String, dynamic>;
      final atlas = Atlas.fromJson({
        'cities': [
          ...nara['cities'] as List,
          {'id': '24208', 'name': '名張市'},
        ],
        'towns': [...nara['towns'] as List, town],
      });
      final county = NationalAtlas(atlas, {});
      final shape = [
        [
          [
            [136.0, 34.0],
            [136.1, 34.0],
            [136.1, 34.1],
            [136.0, 34.0],
          ],
        ],
      ];
      final geometry = preparedFixture({
        '242080001': shape,
        '24208': shape,
        'pref': shape,
      });
      var reads = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (key != 'assets/data/national_territories/24.bin') return null;
        reads++;
        return reads == 1 ? null : geometry;
      });
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );
      await Future.wait([
        county.ensureGeometry('24'),
        county.ensureGeometry('24'),
      ]);
      expect(reads, 2);
      expect(county.residentGeometry, '24');
      expect(atlas.towns[atlas.sourceToTown['242080001']]!.polygons.length, 1);
      await county.ensureGeometry('24');
      expect(reads, 2);
    },
  );
}

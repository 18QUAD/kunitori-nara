import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'prefecture geometry is serialized, replaced, reloadable and save-neutral',
    () async {
      final original = jsonDecode(
        File('assets/data/nara.json').readAsStringSync(),
      );
      final atlas = Atlas.fromJson({
        'cities': [
          ...original['cities'],
          for (final p in ['26', '27']) {'id': '${p}201', 'name': '検証市$p'},
        ],
        'towns': [
          for (final row in original['towns'])
            <String, dynamic>{...row, 'polygons': []},
          for (final p in ['26', '27'])
            {
              'id': '${p}201001001',
              'name': '検証町',
              'cityId': '${p}201',
              'population': 12,
              'area': 1,
              'neighbors': [],
              'polygons': [],
            },
        ],
      });
      final data = NationalAtlas(atlas, {});
      final game = Game(atlas)..setHome('29205043001');
      game.selectAttackTarget('29205041001');
      game.tap('29205041001', DateTime.utc(2026));
      final saved = game.toJson();
      final reads = <String, int>{};
      var active = 0, peak = 0;
      var fail = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final path = utf8.decode(
              message!.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            );
            final pref =
                path.endsWith('nara.json')
                    ? '29'
                    : path.contains('/26.json')
                    ? '26'
                    : '27';
            reads.update(pref, (n) => n + 1, ifAbsent: () => 1);
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            active--;
            if (fail) {
              fail = false;
              return null;
            }
            final shape = [
              [
                [
                  [135.0, 34.0],
                  [136.0, 34.0],
                  [136.0, 35.0],
                  [135.0, 34.0],
                ],
              ],
            ];
            return ByteData.sublistView(
              Uint8List.fromList(
                utf8.encode(
                  jsonEncode(
                    pref == '29'
                        ? original
                        : {
                          'towns': [
                            {'id': '${pref}201001001', 'polygons': shape},
                          ],
                          'cities': [
                            {
                              'id': '${pref}201',
                              'name': '検証市',
                              'polygons': shape,
                            },
                          ],
                          'polygons': shape,
                        },
                  ),
                ),
              ),
            );
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null),
      );
      expect(atlas.towns['29205043001']!.polygons, isEmpty);
      await data.ensureGeometry('29');
      expect(atlas.towns['29205043001']!.polygons, isNotEmpty);
      expect(data.residentGeometry, '29');
      for (final pref in ['26', '27', '26']) {
        await data.ensureGeometry(pref);
        expect(data.residentGeometry, pref);
        expect(atlas.towns['${pref}201001001']!.polygons, hasLength(1));
        final old = pref == '26' ? '27' : '26';
        expect(atlas.towns['${old}201001001']!.polygons, isEmpty);
        expect(atlas.cityPolygons.keys, ['${pref}201']);
        expect(game.toJson(), saved);
        expect(atlas.towns['29205043001']!.polygons, isEmpty);
        expect(atlas.sourceTowns['29205043001']!.polygons, isEmpty);
      }
      expect(reads['26'], 2);
      // A -> B -> A before B starts must await the final A, not reuse stale A.
      await Future.wait([data.ensureGeometry('27'), data.ensureGeometry('26')]);
      expect(data.residentGeometry, '26');
      expect(atlas.towns['26201001001']!.polygons, hasLength(1));
      final converted = <String>[];
      await Future.wait([
        for (final pref in ['27', '26', '27'])
          data.withGeometry(pref, () {
            expect(data.residentGeometry, pref);
            expect(atlas.towns['${pref}201001001']!.polygons, isNotEmpty);
            converted.add(pref);
          }),
      ]);
      expect(converted, ['27', '26', '27']);
      expect(data.residentGeometry, isNull);
      await data.withGeometry('29', () {
        expect(atlas.towns['29205043001']!.polygons, isNotEmpty);
      });
      expect(data.residentGeometry, isNull);
      expect(atlas.towns['29205043001']!.polygons, isEmpty);
      // A failed conversion must also free the temporary geometry.
      await expectLater(
        data.withGeometry('29', () => throw StateError('test')),
        throwsStateError,
      );
      expect(data.residentGeometry, isNull);
      await data.ensureGeometry('29');
      expect(atlas.towns['29205043001']!.polygons, isNotEmpty);
      await data.releaseGeometry();
      expect(atlas.towns['29205043001']!.polygons, isEmpty);
      // Releasing must invalidate a completed ensureGeometry future.
      await data.ensureGeometry('29');
      expect(atlas.towns['29205043001']!.polygons, isNotEmpty);
      expect(peak, 1);
      fail = true;
      final beforeRetry = reads['26']!;
      // Temporary storage failures retry automatically; the caller remains
      // blocked until complete geometry is ready.
      await data.ensureGeometry('26');
      expect(reads['26'], beforeRetry + 2);
      expect(atlas.towns['26201001001']!.polygons, hasLength(1));
      expect(atlas.towns['29205043001']!.polygons, isEmpty);
      expect(game.toJson(), saved);
    },
  );
}

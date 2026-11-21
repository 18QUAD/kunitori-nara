import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NationalAtlas data;
  final now = DateTime.utc(2026, 10, 24);
  setUpAll(() async => data = await NationalAtlas.load());

  test(
    'all 1896 municipalities have a playable office or explicit in-territory hub',
    () {
      final atlas = data.atlas;
      expect(atlas.cities.length, 1896);
      expect(atlas.offices.keys.toSet(), atlas.cities.keys.toSet());
      expect(atlas.officeTownIds.keys.toSet(), atlas.cities.keys.toSet());
      expect(atlas.mapOffices.length, 1916);
      expect(atlas.towns.values.every((t) => t.polygons.isEmpty), isTrue);
      final fallback =
          atlas.offices.values
              .where((o) => o.usesConquestHub)
              .map((o) => o.cityId)
              .toSet();
      expect(fallback, {'46303', '46304', '47381'});
      for (final city in atlas.cities.keys) {
        final town = atlas.officeTownIds[city]!;
        expect(atlas.towns[town]!.cityId, city);
        expect(atlas.sourceToTown[atlas.offices[city]!.sourceTownId], town);
        if (fallback.contains(city)) {
          expect(atlas.mapOffices[city]!.townId, isNull);
          expect(atlas.conquestPlaceName(city), contains('制圧拠点'));
        } else {
          expect(town, atlas.mapOffices[city]!.townId);
        }
      }
    },
  );

  test(
    'every municipality completes on the final tap with no quiz requirement',
    () {
      final atlas = data.atlas;
      for (final city in atlas.cities.keys) {
        final towns = atlas.byCity[city]!;
        final game = Game(atlas, random: Random(42))..startAt(towns.first.id);
        if (towns.length == 1) {
          expect(game.mastered, contains(city));
          continue;
        }
        final last = towns.last;
        game.owned.addAll(towns.where((t) => t.id != last.id).map((t) => t.id));
        if (last.neighbors.isNotEmpty) game.owned.add(last.neighbors.first);
        // A neighbor must not accidentally pre-capture the target itself.
        game.owned.remove(last.id);
        game.everOwned.addAll(game.owned);
        expect(game.cityOwned(city), isFalse);
        expect(game.mastered.contains(city), isFalse);
        game.progress[last.id] = game.requiredTaps(last) - 1;
        expect(game.canAttack(last.id), isTrue, reason: city);
        expect(game.tap(last.id, now), isTrue, reason: city);
        expect(game.cityOwned(city), isTrue);
        expect(game.mastered, contains(city));
        expect(game.quiz, isNull);
        expect(game.canStartQuizAt(atlas.officeTownIds[city]!), isFalse);
        expect(game.message, contains('完全制圧'));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

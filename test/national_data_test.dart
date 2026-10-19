import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NationalAtlas national;
  late Atlas nara;
  setUpAll(() async {
    national = await NationalAtlas.load();
    nara = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
  });

  test('startup retains no detailed coordinates, including Nara sources', () {
    expect(national.residentGeometry, isNull);
    expect(
      national.atlas.towns.values.every((t) => t.polygons.isEmpty),
      isTrue,
    );
    expect(
      national.atlas.sourceTowns.values.every((t) => t.polygons.isEmpty),
      isTrue,
    );
    final original = jsonDecode(
      File('assets/data/nara.json').readAsStringSync(),
    );
    for (final row in original['towns']) {
      row['polygons'] = [];
    }
    expect(
      jsonDecode(File('assets/data/nara_metadata.json').readAsStringSync()),
      original,
    );
  });

  test(
    'real census covers all 47 prefectures and the full national population',
    () {
      final atlas = national.atlas;
      expect(national.prefectures.length, 47);
      expect(atlas.cities.length, 1896);
      expect(atlas.towns.values.map((t) => t.id.substring(0, 2)).toSet(), {
        for (var i = 1; i <= 47; i++) i.toString().padLeft(2, '0'),
      });
      expect(
        atlas.sourceTowns.values.fold<int>(0, (sum, t) => sum + t.population),
        126146099,
      );
      expect(
        atlas.towns.values.fold<int>(0, (sum, t) => sum + t.population),
        126146099,
      );
      for (final city in atlas.byCity.entries) {
        for (final town in city.value) {
          expect(
            town.population,
            atlas.membersByTown[town.id]!.fold<int>(
              0,
              (sum, t) => sum + t.population,
            ),
          );
          for (final id in town.neighbors) {
            expect(atlas.towns[id]!.neighbors, contains(town.id));
          }
        }
      }
      final naraBorders = <String>{};
      for (final t in atlas.towns.values.where(
        (t) => t.cityId.startsWith('29'),
      )) {
        naraBorders.addAll(
          t.neighbors.map((id) => id.substring(0, 2)).where((p) => p != '29'),
        );
      }
      expect(naraBorders, {'24', '26', '27', '30'});
    },
  );

  test(
    'real nationwide expansion preserves every Nara town, fact and saved campaign',
    () {
      final atlas = national.atlas;
      for (final t in nara.towns.values) {
        final actual = atlas.towns[t.id]!;
        expect(actual.name, t.name);
        expect(actual.population, t.population);
        expect(actual.area, t.area);
        expect(
          actual.neighbors.where((id) => id.startsWith('29')).toSet(),
          t.neighbors,
        );
      }
      for (final city in nara.facts.keys) {
        expect(
          atlas.facts[city]!.map((f) => f.id),
          nara.facts[city]!.map((f) => f.id),
        );
      }
      final home = nara.towns.values.firstWhere(
        (t) => t.neighbors.any((id) => nara.towns[id]!.population > 10),
      );
      final target = home.neighbors.firstWhere(
        (id) => nara.towns[id]!.population > 10,
      );
      final old =
          Game(nara)
            ..setHome(home.id)
            ..selectAttackTarget(target);
      for (var i = 0; i < 7; i++) {
        old.tap(target, DateTime.utc(2026));
      }
      old.observe(home.cityId);
      expect(Game.restore(atlas, old.toJson()).toJson(), old.toJson());
      const city = '29362';
      final quizGame = Game(nara)..setHome(nara.officeTownIds[city]!);
      quizGame.owned.addAll(nara.byCity[city]!.map((t) => t.id));
      quizGame.everOwned.addAll(quizGame.owned);
      quizGame.startQuizAt(quizGame.home!, DateTime.utc(2026));
      expect(
        Game.restore(atlas, quizGame.toJson()).toJson(),
        quizGame.toJson(),
      );
    },
  );

  test(
    'every real town can be reached through land borders and component landings',
    () {
      final atlas = national.atlas;
      final reached = <String>{};
      final pending = [...atlas.landingTowns];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reached.add(id)) continue;
        pending.addAll(
          atlas.towns[id]!.neighbors.where((id) => !reached.contains(id)),
        );
      }
      expect(reached.length, atlas.towns.length);
      final game = Game(atlas)..setHome(nara.towns.keys.first);
      final okinawa = atlas.landingTowns.firstWhere(
        (id) => id.startsWith('47'),
      );
      expect(game.canAttack(okinawa), isTrue);
      expect(
        game.requiredTaps(atlas.towns[okinawa]!),
        atlas.towns[okinawa]!.population,
      );
      expect(
        game.requiredTaps(
          atlas.towns.values.firstWhere((t) => t.population == 0),
        ),
        1,
      );
    },
  );

  test(
    'large and offshore geometry retains coverage while inactive prefectures are released',
    () async {
      final atlas = national.atlas;
      String? previous;
      for (final pref in ['29', '01', '29', '13', '27', '47']) {
        await national.ensureGeometry(pref);
        final towns =
            atlas.towns.values.where((t) => t.cityId.startsWith(pref)).toList();
        expect(towns.every((t) => t.polygons.isNotEmpty), isTrue, reason: pref);
        if (pref == '29') {
          for (final town in nara.towns.values) {
            expect(atlas.towns[town.id]!.polygons, town.polygons);
          }
        }
        expect(atlas.prefecturePolygons[pref], isNotEmpty);
        for (final city in atlas.cities.keys.where(
          (id) => id.startsWith(pref),
        )) {
          expect(atlas.cityPolygons[city], isNotEmpty);
        }
        if (previous != null) {
          expect(
            atlas.towns.values
                .where((t) => t.id.startsWith(previous!))
                .every((t) => t.polygons.isEmpty),
            isTrue,
          );
          expect(atlas.prefecturePolygons.containsKey(previous), isFalse);
        }
        if (pref == '13') {
          final points = atlas.prefecturePolygons[pref]!
              .expand((p) => p)
              .expand((r) => r);
          expect(points.any((p) => p.x > 153), isTrue);
          expect(points.any((p) => p.y < 21), isTrue);
        }
        previous = pref;
        final count = towns.fold<int>(0, (sum, t) => sum + t.polygons.length);
        await national.ensureGeometry(pref);
        expect(towns.fold<int>(0, (sum, t) => sum + t.polygons.length), count);
      }
      expect(national.residentGeometry, '47');
    },
  );
}

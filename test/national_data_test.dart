import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';
import 'package:kunitori/national_territory.dart';
import 'package:kunitori/prepared_territory.dart';

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
    'configured sea links connect real towns only after capturing their port',
    () {
      final atlas = national.atlas;
      final game = Game(atlas)..setHome('29205043001');
      expect(atlas.seaNeighbors, isNotEmpty);
      for (final entry in atlas.seaNeighbors.entries) {
        expect(atlas.towns.containsKey(entry.key), isTrue);
        for (final other in entry.value) {
          expect(atlas.towns.containsKey(other), isTrue);
          expect(atlas.seaNeighbors[other], contains(entry.key));
          expect(game.canLand(other), isFalse);
        }
      }
      const departure = '26202008062'; // 舞鶴市・新舞鶴前島埠頭
      const destination = '012030200'; // 小樽市・築港
      expect(game.canAttack(destination), isFalse);
      game.owned.add(departure);
      game.everOwned.add(departure);
      expect(game.canLand(destination), isTrue);
      expect(game.canAttack(destination), isTrue);
      expect(game.canAttack('01202031001'), isFalse);
      game.owned.add(destination);
      expect(game.canLand(destination), isFalse);
      expect(
        game.requiredTaps(atlas.towns[destination]!),
        atlas.towns[destination]!.population,
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
            expect(atlas.towns[town.id]!.polygons, isNotEmpty);
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
  test(
    'prepared directories cover exactly the canonical gameplay towns',
    () async {
      for (var number = 1; number <= 47; number++) {
        final pref = number.toString().padLeft(2, '0');
        final prepared = await PreparedTerritory.load(pref);
        expect(
          prepared.entries.keys.where((id) => id.length > 5).toSet(),
          national.atlas.towns.keys.where((id) => id.startsWith(pref)).toSet(),
        );
      }
    },
  );
  test(
    'prepared national contours match detailed maps without resident geometry',
    () async {
      Offset project(math.Point<double> p) =>
          Offset(40 + (p.x - 122) * 42, 40 + (46 - p.y) * 50);
      for (final pref in ['24', '26', '29', '01', '13', '47']) {
        await national.ensureGeometry(pref);
        final towns =
            national.atlas.towns.values
                .where((t) => t.id.startsWith(pref))
                .toList();
        towns.sort((a, b) => b.polygons.length.compareTo(a.polygons.length));
        final selected = {
          towns.first.id,
          towns[towns.length ~/ 2].id,
          towns.last.id,
        };
        final expected = <String, Path>{};
        for (final id in selected) {
          final path = Path()..fillType = PathFillType.evenOdd;
          for (final polygon in national.atlas.towns[id]!.polygons) {
            for (final ring in polygon) {
              if (ring.isEmpty) continue;
              final first = project(ring.first);
              path.moveTo(first.dx, first.dy);
              for (final point in ring.skip(1)) {
                final p = project(point);
                path.lineTo(p.dx, p.dy);
              }
              path.close();
            }
          }
          expected[id] = path;
        }
        await national.releaseGeometry();
        final actual = await loadNationalTerritory(
          prefecture: pref,
          towns: selected,
          sourceToTown: national.atlas.sourceToTown,
          project: project,
          isCurrent: () => true,
        );
        expect(actual.keys.toSet(), selected);
        expect(national.residentGeometry, isNull);
        expect(national.atlas.cityPolygons, isEmpty);
        for (final id in selected) {
          expect(
            actual[id]!.getBounds(),
            expected[id]!.getBounds(),
            reason: id,
          );
          expect(
            actual[id]!.computeMetrics().map((m) => m.length).toList(),
            expected[id]!.computeMetrics().map((m) => m.length).toList(),
            reason: id,
          );
          actual[id]!.reset();
          expected[id]!.reset();
        }
      }
    },
  );
}

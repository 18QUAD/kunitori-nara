import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NationalAtlas data;
  final now = DateTime.utc(2026, 10, 24);
  setUpAll(() async => data = await NationalAtlas.load());

  Game ready(String city, {bool officeHome = false}) {
    final atlas = data.atlas;
    final game = Game(atlas, random: Random(42));
    game.setHome(
      officeHome ? atlas.officeTownIds[city]! : atlas.byCity[city]!.first.id,
    );
    game.owned.addAll(atlas.byCity[city]!.map((t) => t.id));
    game.everOwned.addAll(game.owned);
    return game;
  }

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
    'all non-Nara cities complete five distinct unambiguous questions and retain territory',
    () {
      final atlas = data.atlas;
      var completed = 0;
      for (final city in atlas.cities.keys.where((c) => !c.startsWith('29'))) {
        final game = ready(city), town = atlas.officeTownIds[city]!;
        final facts = atlas.facts[city]!.where((f) => f.quizEligible).toList();
        expect(facts, hasLength(5), reason: city);
        expect(facts.map((f) => f.id).toSet(), hasLength(5));
        expect(
          facts.every((f) => f.question.isNotEmpty && f.answer.isNotEmpty),
          isTrue,
        );
        expect(game.canStartQuizAt(town), isTrue, reason: city);
        game.startQuizAt(town, now);
        final ids = <String>{};
        for (var question = 0; question < 5; question++) {
          final q = game.quiz!;
          expect(q.choices.toSet(), hasLength(4), reason: q.factId);
          expect(q.choices.where((s) => s == q.answer), hasLength(1));
          if (q.factId.endsWith(':largest')) {
            final members = atlas.byCity[city]!;
            final population = members.fold<int>(
              0,
              (n, t) => max(n, t.population),
            );
            final tiedNames =
                members
                    .where((t) => t.population == population)
                    .map((t) => t.name)
                    .toSet();
            expect(
              q.choices.where(tiedNames.contains),
              hasLength(1),
              reason: q.factId,
            );
          }
          ids.add(q.factId);
          expect(game.answer(q.answer, now), isTrue);
        }
        expect(ids, hasLength(5));
        expect(game.quiz, isNull);
        expect(game.mastered, contains(city));
        expect(game.wins, 1);
        expect(game.cityOwned(city), isTrue);
        expect(game.titles, contains('全国の知恵者'));
        completed++;
      }
      expect(completed, 1857);
    },
  );

  for (final city in ['01101', '24216', '27127', '46303', '46304', '47381']) {
    test(
      '$city restores in-progress questions, loses only the office/hub on failure, and can retry',
      () {
        var game = ready(city, officeHome: true);
        final atlas = data.atlas, town = atlas.officeTownIds[city]!;
        game.startQuizAt(town, now);
        game.answer(game.quiz!.answer, now);
        game.answer(game.quiz!.answer, now);
        final saved = game.toJson();
        game = Game.restore(atlas, saved);
        expect(game.quiz!.correctCount, 2);
        final owned = {...game.owned};
        game.answer(
          game.quiz!.choices.firstWhere((a) => a != game.quiz!.answer),
          now,
        );
        expect(game.owned, owned..remove(town));
        expect(game.mastered.contains(city), isFalse);
        expect(game.losses, 1);
        game = Game.restore(atlas, game.toJson());
        expect(game.isReachable(town), isTrue);
        game.progress[town] = game.requiredTaps(atlas.towns[town]!) - 1;
        expect(game.tap(town, now), isTrue);
        expect(game.canStartQuizAt(town), isTrue);
        game.startQuizAt(town, now);
        for (var i = 0; i < 5; i++) {
          game.answer(game.quiz!.answer, now);
        }
        final completed = Game.restore(atlas, game.toJson());
        expect(completed.mastered, contains(city));
        expect(completed.canStartQuizAt(town), isFalse);
        expect(completed.canPracticeAt(town), isTrue);
      },
    );
  }

  test(
    'loading and releasing regional tips never removes active conquest questions',
    () async {
      const city = '24216';
      final atlas = data.atlas, game = ready(city);
      game.startQuizAt(atlas.officeTownIds[city]!, now);
      game.answer(game.quiz!.answer, now);
      final saved = game.toJson();
      await data.tips!.ensure('24');
      expect(atlas.facts[city]!.where((f) => f.quizEligible), hasLength(5));
      expect(
        atlas.facts[city]!.any((f) => f.id.contains(':national:')),
        isTrue,
      );
      expect(Game.restore(atlas, saved).quiz!.factId, game.quiz!.factId);
      await data.tips!.ensure('01');
      expect(Game.restore(atlas, saved).quiz!.factId, game.quiz!.factId);
      await data.tips!.ensure('29');
    },
  );

  test(
    'previously conquered cities and placeholder reading history remain valid',
    () {
      final game = ready('24216');
      game.seen.add('24216:placeholder:pending');
      final old = game.toJson();
      final restored = Game.restore(data.atlas, old);
      expect(restored.owned, game.owned);
      expect(restored.totalTaps, game.totalTaps);
      expect(restored.quiz, isNull);
      expect(
        restored.canStartQuizAt(data.atlas.officeTownIds['24216']!),
        isTrue,
      );
    },
  );
}

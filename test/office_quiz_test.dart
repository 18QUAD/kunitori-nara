import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';

void main() {
  late Atlas atlas;
  final now = DateTime.utc(2026, 10, 8);
  setUpAll(() {
    atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
  });
  Game ready(String city, {bool officeHome = false}) {
    final game = Game(atlas, random: Random(42));
    game.setHome(
      officeHome ? atlas.officeTownIds[city]! : atlas.byCity[city]!.first.id,
    );
    game.owned.addAll(atlas.byCity[city]!.map((t) => t.id));
    game.everOwned.addAll(game.owned);
    return game;
  }

  test(
    'all offices allow practice before conquest without changing game data',
    () {
      final game = Game(atlas);
      final before = jsonEncode(game.toJson());
      for (final office in atlas.officeTownIds.values) {
        final questions = game.practiceQuestionsAt(office);
        expect(questions, hasLength(5));
        expect(questions.map((q) => q.factId).toSet(), hasLength(5));
        expect(questions.every((q) => q.choices.contains(q.answer)), isTrue);
        expect(jsonEncode(game.toJson()), before);
        expect(game.canStartQuizAt(office), isFalse);
      }
      final ordinaryTown = atlas.towns.keys.firstWhere(
        (id) => !atlas.officeTownIds.values.contains(id),
      );
      expect(game.practiceQuestionsAt(ordinaryTown), isEmpty);
    },
  );

  test('every difficulty gives two distinct decoys and exactly one joke', () {
    final seenFacts = <String>{};
    final jokesSeen = <String>{};
    for (final difficulty in Difficulty.values) {
      final game = Game(atlas, random: Random(42))..difficulty = difficulty;
      for (final office in atlas.officeTownIds.values) {
        for (var attempt = 0; attempt < 10; attempt++) {
          for (final q in game.practiceQuestionsAt(office)) {
            final fact = atlas.facts[atlas.towns[office]!.cityId]!.singleWhere(
              (f) => f.id == q.factId,
            );
            final normal = {...fact.decoys, '奈良公園', '関西国際空港', '富士山'};
            final wrong = q.choices.where((a) => a != q.answer).toList();
            expect(q.choices.toSet(), hasLength(4), reason: q.factId);
            expect(q.choices.where((a) => a == q.answer), hasLength(1));
            expect(
              wrong.where(normal.contains),
              hasLength(2),
              reason: q.factId,
            );
            final joke = wrong.where((a) => !normal.contains(a)).single;
            expect(joke, isNotEmpty);
            jokesSeen.add(joke);
            seenFacts.add(q.factId);
          }
        }
      }
    }
    expect(
      seenFacts,
      atlas.facts.values
          .expand((fs) => fs)
          .where((f) => f.quizEligible)
          .map((f) => f.id)
          .toSet(),
    );
    expect(jokesSeen.length, greaterThan(6));
  });

  test('numeric alternatives differ by at least a quarter of the answer', () {
    int parse(String value) =>
        int.parse(value.replaceAll(RegExp(r'[^0-9]'), ''));
    for (final fact in atlas.facts.values.expand((fs) => fs)) {
      if (!fact.id.endsWith(':count') && !fact.id.endsWith(':population')) {
        continue;
      }
      final answer = parse(fact.answer);
      for (final decoy in fact.decoys) {
        expect(
          (parse(decoy) - answer).abs(),
          greaterThanOrEqualTo(answer / 4),
          reason: fact.id,
        );
      }
    }
  });

  test('generated office constants match the bundled source records', () {
    final data = jsonDecode(
      File('assets/data/nara_offices.json').readAsStringSync(),
    );
    expect(data['offices'], hasLength(39));
    for (final record in data['offices']) {
      final office = atlas.offices[record['cityId']]!;
      expect(office.name, record['name']);
      expect(office.address, record['address']);
      expect(office.sourceTownId, record['sourceTownId']);
      expect([office.longitude, office.latitude], record['point']);
      expect(office.officialUrl, record['officialUrl']);
      expect(
        record['coordinateSourceSha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    }
  });

  test('pre-upgrade saves retain mastered cities and possessions', () {
    final old = ready('29205');
    old.mastered.add('29205');
    old.wins = 2;
    old.totalTaps = 10;
    final data = old.toJson()..remove('quizRule');
    final loaded = Game.restore(atlas, data);
    expect(loaded.home, old.home);
    expect(loaded.owned, old.owned);
    expect(loaded.everOwned, old.everOwned);
    expect(loaded.mastered, old.mastered);
    expect(loaded.totalTaps, 10);
    expect(loaded.wins, 2);
  });

  test('all 39 offices map to a containing town and five valid questions', () {
    expect(atlas.offices.keys.toSet(), atlas.cities.keys.toSet());
    for (final office in atlas.offices.values) {
      final town = atlas.towns[atlas.officeTownIds[office.cityId]]!;
      expect(town.cityId, office.cityId);
      expect(
        town.polygons.any((polygon) {
          final path = Path()..fillType = PathFillType.evenOdd;
          for (final ring in polygon) {
            path.moveTo(ring.first.x, ring.first.y);
            for (final p in ring.skip(1)) {
              path.lineTo(p.x, p.y);
            }
            path.close();
          }
          return path.contains(Offset(office.longitude, office.latitude));
        }),
        isTrue,
        reason: office.name,
      );
      final game = ready(office.cityId)..startQuizAt(town.id, now);
      final q = game.quiz!;
      expect([q, ...q.remaining].map((q) => q.factId).toSet(), hasLength(5));
      expect(
        [q, ...q.remaining].every(
          (q) => q.choices.toSet().length == 4 && q.choices.contains(q.answer),
        ),
        isTrue,
      );
    }
    expect(atlas.towns[atlas.officeTownIds['29402']]!.name, '橘');
    expect(atlas.towns[atlas.officeTownIds['29210']]!.name, '本町');
    expect(atlas.towns[atlas.officeTownIds['29343']]!.name, '勢野西');
  });
  test('only the office of a fully owned unmastered city starts a quiz', () {
    final game = ready('29205');
    final office = atlas.officeTownIds['29205']!;
    final other = atlas.byCity['29205']!.firstWhere((t) => t.id != office).id;
    game.startQuizAt(other, now);
    expect(game.quiz, isNull);
    game.owned.remove(other);
    game.startQuizAt(office, now);
    expect(game.quiz, isNull);
    game.owned.add(other);
    game.startQuizAt(office, now);
    final q = game.quiz;
    game.startQuizAt(office, now.add(const Duration(seconds: 2)));
    expect(game.quiz, same(q));
  });
  test(
    'question three resumes with its deadline and clears only after question five',
    () {
      final game = ready('29205')
        ..startQuizAt(atlas.officeTownIds['29205']!, now);
      game.answer(game.quiz!.answer, now.add(const Duration(seconds: 1)));
      game.answer(game.quiz!.answer, now.add(const Duration(seconds: 2)));
      final loaded = Game.restore(atlas, jsonDecode(jsonEncode(game.toJson())));
      expect(loaded.quiz!.correctCount, 2);
      expect(loaded.quiz!.deadline, game.quiz!.deadline);
      expect(
        loaded.quiz!.remaining.map((q) => q.factId),
        game.quiz!.remaining.map((q) => q.factId),
      );
      for (var i = 0; i < 3; i++) {
        loaded.answer(loaded.quiz!.answer, now.add(Duration(seconds: i + 3)));
      }
      expect(loaded.quiz, isNull);
      expect(loaded.mastered, {'29205'});
      expect(loaded.wins, 1);
      loaded.startQuizAt(atlas.officeTownIds['29205']!, now);
      expect(loaded.quiz, isNull);
    },
  );
  test(
    'office home can be lost, restored from save, recaptured and challenged again',
    () {
      final game = ready('29205', officeHome: true);
      final office = game.home!;
      final before = {...game.owned};
      game.startQuizAt(office, now);
      game.answer('wrong', now);
      expect(before.difference(game.owned), {office});
      final loaded = Game.restore(atlas, jsonDecode(jsonEncode(game.toJson())));
      expect(loaded.home, office);
      expect(loaded.owned, isNot(contains(office)));
      expect(loaded.canAttack(office), isTrue);
      loaded.progress[office] = loaded.requiredTaps(atlas.towns[office]!) - 1;
      expect(loaded.tap(office, now), isTrue);
      expect(loaded.quiz, isNull);
      expect(loaded.canStartQuizAt(office), isTrue);
    },
  );
  test(
    'timeout after four correct answers loses only the office and records one failure',
    () {
      final game = ready('29402');
      final before = {...game.owned};
      game.startQuizAt(atlas.officeTownIds['29402']!, now);
      for (var i = 0; i < 4; i++) {
        game.answer(game.quiz!.answer, now.add(Duration(seconds: i + 1)));
      }
      final end = game.quiz!.deadline;
      expect(game.expire(end), isTrue);
      expect(game.expire(end), isFalse);
      expect(game.losses, 1);
      expect(game.wins, 0);
      expect(before.difference(game.owned), {atlas.officeTownIds['29402']!});
    },
  );
  test('malformed pending questions and unknown rules are rejected', () {
    final game = ready('29205')
      ..startQuizAt(atlas.officeTownIds['29205']!, now);
    final data = jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>;
    data['quiz']['remaining'].removeLast();
    expect(() => Game.restore(atlas, data), throwsFormatException);
    final future = game.toJson()..['quizRule'] = 'future';
    expect(() => Game.restore(atlas, future), throwsFormatException);
  });
}

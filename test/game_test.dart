import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/save_store.dart';

void main() {
  late Atlas atlas;
  final now = DateTime.utc(2026, 10, 6);
  setUpAll(() {
    atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  test('full Nara data has symmetric boundary adjacency and is connected', () {
    expect(atlas.cities.length, 39);
    expect(atlas.towns.length, 3078);
    expect(atlas.towns.values.fold(0, (s, t) => s + t.population), 1324473);
    final reached = <String>{};
    final queue = [atlas.towns.keys.first];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!reached.add(id)) continue;
      final town = atlas.towns[id]!;
      expect(town.neighbors.contains(id), false);
      expect(town.polygons, isNotEmpty);
      for (final n in town.neighbors) {
        expect(atlas.towns[n]!.neighbors, contains(id));
        if (!reached.contains(n)) queue.add(n);
      }
    }
    expect(reached.length, 3078);
  });
  test(
    'cannot attack remote, owned or unstarted territories; exact taps conquer',
    () {
      final g = Game(atlas);
      final home = atlas.towns.values.first;
      expect(g.tap(home.id, now), false);
      expect(g.totalTaps, 0);
      g.setHome(home.id);
      final near = atlas.towns[home.neighbors.first]!;
      final far = atlas.towns.values.firstWhere(
        (t) => t.id != home.id && !t.neighbors.contains(home.id),
      );
      expect(g.canAttack(far.id), false);
      g.tap(far.id, now);
      expect(g.totalTaps, 0);
      expect(g.canAttack(home.id), false);
      for (var i = 1; i < g.requiredTaps(near); i++) {
        expect(g.tap(near.id, now), false);
      }
      expect(g.owned.contains(near.id), false);
      expect(g.tap(near.id, now), true);
      expect(g.owned, contains(near.id));
      expect(g.progress.containsKey(near.id), false);
      final taps = g.totalTaps;
      g.tap(near.id, now);
      expect(g.totalTaps, taps);
    },
  );
  test('difficulty changes cost, zero population still needs taps', () {
    final g = Game(atlas);
    final t = atlas.towns.values.firstWhere((t) => t.population == 0);
    g.difficulty = Difficulty.casual;
    expect(g.requiredTaps(t), 3);
    g.difficulty = Difficulty.standard;
    expect(g.requiredTaps(t), 6);
    g.difficulty = Difficulty.expert;
    expect(g.requiredTaps(t), 11);
  });
  Game completeCity() {
    final city = atlas.byCity.entries.reduce(
      (a, b) => a.value.length < b.value.length ? a : b,
    );
    final g = Game(atlas, random: Random(2));
    g.setHome(city.value.first.id);
    // Fixture starts one tap before the final region is captured.
    final last = city.value.last;
    for (final t in city.value.where((t) => t.id != last.id)) {
      g.owned.add(t.id);
      g.everOwned.add(t.id);
    }
    // A city may have separated territories; own a bordering region as a route.
    final route = last.neighbors.first;
    g.owned.add(route);
    g.everOwned.add(route);
    g.seen.add(atlas.facts[city.key]!.first.id);
    for (var i = 0; i < g.requiredTaps(last); i++) {
      g.tap(last.id, now);
    }
    expect(g.quiz, isNotNull);
    return g;
  }

  test(
    'city completion uses a seen fact; correct answer certifies control once',
    () {
      final g = completeCity();
      final q = g.quiz!;
      expect(g.seen, contains(q.factId));
      expect(q.choices.toSet().length, 4);
      expect(g.canAttack(atlas.towns.keys.first), false);
      expect(g.answer(q.answer, now.add(const Duration(seconds: 1))), true);
      expect(g.mastered, contains(q.cityId));
      expect(g.wins, 1);
      expect(g.answer(q.answer, now), null);
      expect(g.wins, 1);
    },
  );
  test('failure removes territory, preserves home and lifetime progress', () {
    final g = completeCity();
    final before = g.owned.length;
    final ever = g.everOwned.length;
    g.totalTaps = 1000;
    g.titles.add('千里の旅人');
    expect(g.answer('wrong', now), false);
    expect(g.owned.length, lessThan(before));
    expect(g.owned, contains(g.home));
    expect(g.everOwned.length, ever);
    expect(g.totalTaps, 1000);
    expect(g.titles, contains('千里の旅人'));
  });
  test('saved quiz retains deadline; reopening expires it exactly once', () {
    final g = completeCity();
    final q = g.quiz!;
    final restored = Game.restore(atlas, jsonDecode(jsonEncode(g.toJson())));
    expect(restored.quiz!.deadline, q.deadline);
    expect(restored.expire(q.deadline), true);
    expect(restored.losses, 1);
    expect(restored.expire(q.deadline.add(const Duration(days: 1))), false);
    expect(restored.losses, 1);
  });
  test('answer at the deadline fails even if correct', () {
    final g = completeCity();
    final q = g.quiz!;
    expect(g.answer(q.answer, q.deadline), false);
  });
  test(
    'save restores partial taps and latest rapid write; corrupt data stays intact',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SaveStore(prefs);
      final g = Game(atlas);
      g.setHome(atlas.towns.keys.first);
      final next = atlas.towns[g.home]!.neighbors.first;
      g.tap(next, now);
      final first = store.save(g);
      g.tap(next, now);
      final second = store.save(g);
      await Future.wait([first, second]);
      final restored = store.load(atlas);
      expect(restored.progress[next], 2);
      expect(restored.home, g.home);
      expect(store.error, isNull);
      await prefs.setString(SaveStore.key, '{broken');
      expect(() => store.load(atlas), throwsFormatException);
      expect(prefs.getString(SaveStore.key), '{broken');
    },
  );
  test('invalid and future-version save data is rejected', () {
    final g = Game(atlas);
    g.setHome(atlas.towns.keys.first);
    expect(
      () => Game.restore(atlas, {...g.toJson(), 'version': 999}),
      throwsFormatException,
    );
    expect(
      () => Game.restore(atlas, {
        ...g.toJson(),
        'owned': ['invalid'],
      }),
      throwsFormatException,
    );
  });
}

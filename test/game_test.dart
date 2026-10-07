import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kunitori/territory_map.dart';
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
  test('regional tap counts survive reload and reject inactive taps', () {
    final g = Game(atlas);
    final home = atlas.towns.values.firstWhere((t) => t.neighbors.isNotEmpty);
    g.setHome(home.id);
    final target = atlas.towns[home.neighbors.first]!;
    g.tap(home.id, now);
    expect(g.cityTaps, isEmpty);
    g.tap(target.id, now);
    expect(g.cityTaps[target.cityId], 1);
    final restored = Game.restore(atlas, jsonDecode(jsonEncode(g.toJson())));
    expect(restored.cityTaps[target.cityId], 1);
    expect(restored.cityTapsComplete, isTrue);
    final legacy =
        g.toJson()
          ..remove('cityTaps')
          ..remove('cityTapsComplete');
    final migrated = Game.restore(atlas, legacy);
    expect(migrated.totalTaps, 1);
    expect(migrated.cityTapsComplete, isFalse);
  });
  test('full Nara data has symmetric boundary adjacency and is connected', () {
    expect(atlas.cities.length, 39);
    expect(atlas.sourceTowns.length, 3078);
    expect(atlas.towns.length, lessThan(3078));
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
    expect(reached.length, atlas.towns.length);
  });
  test('chome and small districts combine with totals preserved', () {
    final aoyama = atlas.byCity['29201']!.singleWhere((t) => t.name == '青山');
    final members = atlas.membersByTown[aoyama.id]!;
    expect(members.length, 9);
    expect(aoyama.population, members.fold<int>(0, (s, t) => s + t.population));
    expect(atlas.towns.values.any((t) => t.name.endsWith('丁目')), false);
    expect(
      atlas.towns.values.fold<double>(0, (s, t) => s + t.area),
      closeTo(
        atlas.sourceTowns.values.fold<double>(0, (s, t) => s + t.area),
        0.000001,
      ),
    );
    final achiga = atlas.byCity['29443']!.singleWhere((t) => t.name == '阿知賀');
    expect(atlas.membersByTown[achiga.id]!.length, 12);
    // Census codes occasionally mix different towns; do not collapse those names.
    expect(atlas.byCity['29206']!.where((t) => t.name == '朝倉台西'), hasLength(1));
    expect(atlas.byCity['29206']!.where((t) => t.name == '朝倉台東'), hasLength(1));
  });
  test('legacy home and partial district acquisitions migrate to towns', () {
    final groups =
        atlas.membersByTown.values
            .where((ts) => ts.length > 1 && ts[1].population > 2)
            .toList();
    final home = groups.first;
    final target = groups[1];
    final old = Game(atlas).toJson()..remove('territoryUnit');
    old['home'] = home.last.id;
    old['owned'] = [home.last.id, target.first.id];
    old['everOwned'] = old['owned'];
    old['progress'] = {target[1].id: 2};
    old['totalTaps'] = target.first.population + 2;
    final migrated = Game.restore(atlas, old);
    final homeId = atlas.sourceToTown[home.last.id]!;
    final targetId = atlas.sourceToTown[target.first.id]!;
    expect(migrated.home, homeId);
    expect(migrated.owned, contains(homeId));
    expect(migrated.owned, isNot(contains(targetId)));
    expect(migrated.progress[targetId], target.first.population + 2);
    expect(
      Game.restore(atlas, migrated.toJson()).population,
      migrated.population,
    );
    expect(migrated.totalTaps, old['totalTaps']);
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
  test('each tap adds one person, independent of difficulty', () {
    final t = atlas.towns.values.firstWhere(
      (t) => t.population > 2 && t.neighbors.isNotEmpty,
    );
    for (final difficulty in Difficulty.values) {
      final g = Game(atlas)..difficulty = difficulty;
      g.setHome(t.neighbors.first);
      final initial = g.population;
      expect(g.requiredTaps(t), t.population);
      for (var i = 1; i <= t.population; i++) {
        expect(g.tap(t.id, now), i == t.population);
        expect(g.population, initial + i);
      }
      expect(g.owned, contains(t.id));
    }
  });
  test('45 residents require 45 taps even after 16 taps', () {
    final town = atlas.towns.values.firstWhere((t) => t.population == 45);
    final g = Game(atlas)..setHome(town.neighbors.first);
    expect(g.requiredTaps(town), 45);
    for (var i = 0; i < 16; i++) {
      expect(g.tap(town.id, now), false);
    }
    expect(g.progress[town.id], 16);
    expect(g.owned.contains(town.id), false);
  });
  test('town color changes only at 10 percent population thresholds', () {
    final town = atlas.towns.values.firstWhere((t) => t.population == 45);
    final g = Game(atlas);
    const initial = Color(0xFFEEC47C), conquered = Color(0xFF7AE1BB);
    g.progress[town.id] = 4;
    expect(townFillColor(town, g, reachable: true), initial);
    g.progress[town.id] = 5;
    final tenPercent = Color.lerp(initial, conquered, 0.1);
    expect(townFillColor(town, g, reachable: true), tenPercent);
    g.progress[town.id] = 8;
    expect(townFillColor(town, g, reachable: true), tenPercent);
    g.progress[town.id] = 9;
    expect(
      townFillColor(town, g, reachable: true),
      Color.lerp(initial, conquered, 0.2),
    );
    g.progress[town.id] = 44;
    expect(
      townFillColor(town, g, reachable: true),
      Color.lerp(initial, conquered, 0.9),
    );
    g.owned.add(town.id);
    expect(townFillColor(town, g, reachable: true), conquered);
  });
  test('zero population takes one tap without adding population', () {
    final t = atlas.towns.values.firstWhere(
      (t) => t.population == 0 && t.neighbors.isNotEmpty,
    );
    final g = Game(atlas);
    g.setHome(t.neighbors.first);
    final initial = g.population;
    expect(g.requiredTaps(t), 1);
    expect(g.tap(t.id, now), true);
    expect(g.population, initial);
  });
  test('legacy partial progress adapts while acquired territories remain', () {
    final t = atlas.towns.values.firstWhere(
      (t) => t.population == 0 && t.neighbors.isNotEmpty,
    );
    final g = Game(atlas)..setHome(t.neighbors.first);
    final legacy = g.toJson()..remove('tapRule');
    legacy['progress'] = {t.id: 2};
    legacy['totalTaps'] = 2;
    final restored = Game.restore(atlas, legacy);
    expect(restored.home, g.home);
    expect(restored.owned, g.owned);
    expect(restored.progress[t.id], 0);
    expect(restored.tap(t.id, now), true);
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
  test(
    'legacy district quiz updates to towns without extending its deadline',
    () {
      final g = completeCity();
      final old = g.toJson()..remove('territoryUnit');
      final ids =
          g.owned
              .expand((id) => atlas.membersByTown[id]!.map((t) => t.id))
              .toList();
      old['owned'] = ids;
      old['everOwned'] = ids;
      final q = old['quiz'] as Map<String, dynamic>;
      final count =
          atlas.sourceTowns.values
              .where((t) => t.cityId == g.quiz!.cityId)
              .length;
      q['question'] = '旧町丁字の問題';
      q['answer'] = '$count町丁字';
      q['choices'] = [
        '$count町丁字',
        '${count + 1}町丁字',
        '${count + 2}町丁字',
        '${count + 3}町丁字',
      ];
      final migrated = Game.restore(atlas, old);
      expect(migrated.quiz!.deadline, g.quiz!.deadline);
      expect(migrated.quiz!.question, isNot('旧町丁字の問題'));
      expect(migrated.answer(migrated.quiz!.answer, now), true);
    },
  );
  test('saved quiz with old oaza names loads with the same deadline', () {
    final g = Game(atlas);
    final towns = atlas.byCity['29453']!;
    g.setHome(towns.first.id);
    g.owned.addAll(towns.map((t) => t.id));
    g.everOwned.addAll(g.owned);
    g.seen.add('29453:largest');
    g.startQuiz('29453', now);
    final saved = g.toJson();
    final q = saved['quiz'] as Map<String, dynamic>;
    q['answer'] = '大字${g.quiz!.answer}';
    q['choices'] = g.quiz!.choices.map((name) => '大字$name').toList();
    final restored = Game.restore(atlas, saved);
    expect(restored.quiz!.answer, g.quiz!.answer);
    expect(restored.quiz!.deadline, g.quiz!.deadline);
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

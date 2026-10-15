import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/map_view.dart';

void main() {
  late Atlas nara, combined;
  setUpAll(() {
    final data =
        jsonDecode(File('assets/data/nara.json').readAsStringSync())
            as Map<String, dynamic>;
    nara = Atlas.fromJson(data);
    // Deliberately small fixtures, never included in production assets.
    Map<String, dynamic> town(
      String id,
      String name,
      int population,
      List<String> neighbors,
    ) => {
      'id': id,
      'name': name,
      'cityId': '26201',
      'population': population,
      'area': 1,
      'neighbors': neighbors,
      'polygons': <dynamic>[],
    };
    combined = Atlas.fromJson({
      'cities': [
        ...data['cities'] as List,
        {'id': '26201', 'name': '検証用市'},
      ],
      'towns': [
        ...data['towns'] as List,
        town('26201001001', '中央一丁目', 2, ['26201001002']),
        town('26201001002', '中央二丁目', 3, ['26201001001', '26201001003']),
        town('26201001003', '西町', 0, ['26201001002']),
      ],
    });
  });

  test(
    'consuming import rows retains populations, IDs, graph and legacy saves',
    () {
      final raw =
          jsonDecode(File('assets/data/nara.json').readAsStringSync())
              as Map<String, dynamic>;
      final consumed = Atlas.fromJson(raw, consumeTownRows: true);
      expect(raw['towns'], isEmpty);
      expect(consumed.sourceToTown, nara.sourceToTown);
      for (final town in nara.towns.values) {
        expect(consumed.towns[town.id]!.neighbors, town.neighbors);
        expect(consumed.towns[town.id]!.population, town.population);
      }
      final game = Game(nara)..setHome('29205043001');
      game.selectAttackTarget('29205041001');
      game.tap('29205041001', DateTime.utc(2026));
      expect(Game.restore(consumed, game.toJson()).toJson(), game.toJson());
    },
  );

  test(
    'Nara IDs, facts and unfinished campaign survive adding national towns',
    () {
      expect(combined.byCity.keys, containsAll(nara.byCity.keys));
      for (final town in nara.towns.values) {
        final expanded = combined.towns[town.id]!;
        expect(expanded.name, town.name);
        expect(expanded.population, town.population);
        expect(expanded.neighbors, town.neighbors);
      }
      final home = nara.towns.values.firstWhere(
        (t) => t.neighbors.any((id) => nara.towns[id]!.population > 3),
      );
      final target = home.neighbors.firstWhere(
        (id) => nara.towns[id]!.population > 3,
      );
      final old =
          Game(nara)
            ..setHome(home.id)
            ..selectAttackTarget(target);
      old.tap(target, DateTime.utc(2026));
      old.observe(home.cityId);
      final saved = old.toJson();
      final restored = Game.restore(combined, saved);
      expect(restored.toJson(), saved);
    },
  );

  test(
    'active Nara quiz keeps its questions, answers and absolute deadline',
    () {
      const city = '29362';
      final old = Game(nara)..setHome(nara.officeTownIds[city]!);
      old.owned.addAll(nara.byCity[city]!.map((t) => t.id));
      old.everOwned.addAll(old.owned);
      old.startQuizAt(old.home!, DateTime.utc(2026));
      final saved = old.toJson();
      final restored = Game.restore(combined, saved);
      expect(restored.toJson(), saved);
      expect(restored.quiz!.deadline, old.quiz!.deadline);
    },
  );

  test(
    'other prefectures group chome without merging distinct named towns',
    () {
      final towns = combined.byCity['26201']!;
      expect(towns, hasLength(2));
      final home = towns.firstWhere((t) => t.name == '西町');
      final target = towns.firstWhere((t) => t.name == '中央');
      expect(target.population, 5);
      final g = Game(combined)..setHome(home.id);
      for (var i = 0; i < 4; i++) {
        expect(g.tap(target.id, DateTime.utc(2026)), isFalse);
        expect(g.population, i + 1);
      }
      expect(g.tap(target.id, DateTime.utc(2026)), isTrue);
      expect(g.population, 5);
      expect(g.totalTaps, 5);
      expect(g.requiredTaps(home), 1);
      expect(g.quiz, isNull);
      expect(g.tipsFor().every((f) => f.category == '仮tips'), isTrue);
      expect(g.tipsFor().any((f) => f.text.contains('準備中')), isTrue);
    },
  );

  test('standalone numeric chome names are retained as real towns', () {
    final data =
        jsonDecode(File('assets/data/nara.json').readAsStringSync())
            as Map<String, dynamic>;
    final atlas = Atlas.fromJson({
      'cities': [
        ...data['cities'] as List,
        {'id': '11214', 'name': '春日部市'},
      ],
      'towns': [
        ...data['towns'] as List,
        for (final entry in {'112140140': '八丁目', '112140150': '大字二丁目'}.entries)
          {
            'id': entry.key,
            'name': entry.value,
            'cityId': '11214',
            'population': 42,
            'area': 1,
            'neighbors': <String>[],
            'polygons': <dynamic>[],
          },
      ],
    });
    expect(atlas.byCity['11214']!.map((t) => t.name), ['八丁目', '二丁目']);
    expect(atlas.byCity['11214']!.map((t) => t.population), [42, 42]);
  });

  test('legacy map view defaults to Nara, invalid prefectures are ignored', () {
    const view = MapViewState(
      center: Offset(550, 750),
      scale: 1,
      selected: null,
      cityId: null,
    );
    final legacy =
        view.toJson()
          ..remove('prefectureId')
          ..remove('nationalView');
    final restored = MapViewState.fromJson(legacy, combined)!;
    expect(restored.prefectureId, '29');
    expect(restored.nationalView, isFalse);
    expect(
      MapViewState.fromJson({...legacy, 'prefectureId': '99'}, combined),
      isNull,
    );
    final national =
        MapViewState.fromJson({
          ...legacy,
          'prefectureId': '26',
          'nationalView': true,
        }, combined)!;
    expect(national.nationalView, isTrue);
    expect(national.prefectureId, '26');
  });

  test(
    'landings connect islands in both directions without changing borders',
    () {
      combined.enableSeaTravel();
      final landing = combined.byCity['26201']!.firstWhere(
        (t) => t.name == '中央',
      );
      final inland = combined.byCity['26201']!.firstWhere(
        (t) => t.name == '西町',
      );
      final game = Game(combined)..setHome(nara.towns.keys.first);
      expect(game.isReachable(landing.id), isTrue);
      expect(game.isReachable(inland.id), isFalse);
      expect(landing.neighbors, {inland.id});
      for (var i = 0; i < 5; i++) {
        game.tap(landing.id, DateTime.utc(2026));
      }
      expect(game.owned, contains(landing.id));
      expect(game.isReachable(inland.id), isTrue);
      expect(game.tap(inland.id, DateTime.utc(2026)), isTrue);
      expect(game.totalTaps, 6);
      expect(game.cityOwned('26201'), isTrue);
      expect(game.quiz, isNull);
      expect(game.message, contains('制圧クイズは準備中'));
      final restored = Game.restore(combined, game.toJson());
      expect(restored.toJson(), game.toJson());

      final islandHome = Game(combined)..setHome(inland.id);
      final mainlandLanding = combined.landingTowns.firstWhere(
        (id) => id.startsWith('29'),
      );
      expect(islandHome.isReachable(mainlandLanding), isTrue);
      expect(islandHome.canLand(landing.id), isFalse);
    },
  );

  test(
    'prefecture-only selection shows placeholder tips during a Nara campaign',
    () {
      final home = nara.towns.values.firstWhere((t) => t.neighbors.isNotEmpty);
      final game = Game(combined)..setHome(home.id);
      game.selectAttackTarget(home.neighbors.first);
      final tips = game.tipsFor(selectedPrefecture: '26');
      expect(tips, isNotEmpty);
      expect(
        tips.every((f) => f.category == '仮tips' && !f.quizEligible),
        isTrue,
      );
      expect(
        game.tipsFor(selectedCity: '26201').every((f) => f.category == '仮tips'),
        isTrue,
      );
      expect(
        game
            .tipsFor(selectedTown: combined.byCity['26201']!.first.id)
            .every((f) => f.category == '仮tips'),
        isTrue,
      );
    },
  );

  test(
    'prefecture progress excludes other prefectures and clamps partial taps',
    () {
      final home = nara.towns.values.firstWhere((t) => t.population > 3);
      final target = nara.towns.values.firstWhere(
        (t) => t.id != home.id && t.population > 3,
      );
      final other = combined.byCity['26201']!.firstWhere((t) => t.name == '中央');
      final game = Game(combined)..setHome(home.id);
      game.progress[target.id] = 3;
      game.owned.add(other.id);
      game.progress[other.id] = 99; // Owned towns must never be counted twice.
      final saved = game.toJson();
      expect(combined.prefecturePopulations['29'], nara.totalPopulation);
      expect(combined.prefecturePopulations['26'], 5);
      expect(game.currentPrefecturePopulation('29'), home.population + 3);
      expect(game.currentPrefecturePopulation('26'), 5);
      expect(game.population, home.population + 8);
      expect(game.toJson(), saved);
      game.owned.remove(other.id);
      expect(game.currentPrefecturePopulation('26'), 5);
      expect(game.currentPrefecturePopulation('29'), home.population + 3);
    },
  );
}

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
}

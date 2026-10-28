import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/save_store.dart';

class CountingGame extends Game {
  CountingGame(super.atlas);
  int encodes = 0;
  @override
  Map<String, dynamic> toJson() {
    encodes++;
    return super.toJson();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Atlas atlas;
  setUpAll(() {
    atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
  });
  Future<(CountingGame, SaveStore)> fixture() async {
    SharedPreferences.setMockInitialValues({});
    final store = SaveStore(await SharedPreferences.getInstance());
    final g = CountingGame(atlas);
    final home = atlas.towns.values.firstWhere(
      (t) => t.neighbors.any((id) => atlas.towns[id]!.population > 1000),
    );
    g.setHome(home.id);
    g.selectAttackTarget(
      home.neighbors.firstWhere((id) => atlas.towns[id]!.population > 1000),
    );
    return (g, store);
  }

  test(
    '100 rapid taps encode once, restore every count, and never notify unchanged UI',
    () async {
      final (g, store) = await fixture();
      int notifications = 0;
      store.onChanged = () => notifications++;
      final completions = <Future<void>>[];
      for (var i = 0; i < 100; i++) {
        g.tap(g.attackTarget!, DateTime.now());
        completions.add(store.queueSave(g));
      }
      expect(g.encodes, 0);
      await store.flush();
      await Future.wait(completions);
      final restored = store.load(atlas);
      expect(restored.totalTaps, 100);
      expect(restored.progress, g.progress);
      expect(restored.home, g.home);
      expect(g.encodes, 1);
      expect(notifications, 0);
      expect(store.saving, false);
    },
  );
  test(
    'fixed save window completes without waiting for taps to stop',
    () async {
      final (g, store) = await fixture();
      for (var i = 0; i < 8; i++) {
        g.tap(g.attackTarget!, DateTime.now());
        store.queueSave(g);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(g.encodes, greaterThanOrEqualTo(1));
      expect(g.encodes, lessThan(8));
      await store.flush();
      expect(store.load(atlas).totalTaps, 8);
    },
  );
  test(
    'immediate replacement cannot be overwritten by older queued game',
    () async {
      final (g, store) = await fixture();
      g.tap(g.attackTarget!, DateTime.now());
      final pending = store.queueSave(g);
      final replacement = CountingGame(atlas)..setHome(g.home!);
      await store.save(replacement);
      await pending;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(store.load(atlas).totalTaps, 0);
      expect(g.encodes, 0);
    },
  );
  test(
    'tips cache reuses results and refreshes when regional data changes',
    () async {
      final (g, _) = await fixture();
      final city = atlas.towns[g.home]!.cityId;
      final first = g.tipsFor(selectedCity: city);
      expect(identical(first, g.tipsFor(selectedCity: city)), true);
      final original = atlas.facts[city]!;
      atlas.facts[city] = [...original];
      expect(identical(first, g.tipsFor(selectedCity: city)), false);
      atlas.facts[city] = original;
      expect(
        atlas.cityPopulations[city],
        atlas.byCity[city]!.fold<int>(0, (sum, t) => sum + t.population),
      );
    },
  );
}

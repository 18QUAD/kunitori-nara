import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';
import 'package:kunitori/compact_towns.dart';
import 'package:kunitori/lazy_city_facts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'compact index preserves full graph, office rules, and lazy metadata',
    () async {
      final n = await NationalAtlas.load();
      final a = n.atlas;
      expect(a.towns.length, 141900);
      expect(a.sourceTowns, isEmpty);
      expect(a.membersByTown, isEmpty);
      expect(a.towns, isA<CompactTowns>());
      expect(a.facts, isA<LazyCityFacts>());
      final meta = jsonDecode(
        File('assets/data/compact/index.json').readAsStringSync(),
      );
      final rows = [
        for (final path in meta['townFiles'])
          ...(jsonDecode(File('assets/data/compact/$path').readAsStringSync())
              as List),
      ];
      final ids = [for (final row in rows) row[0] as String];
      for (final row in rows) {
        final t = a.towns[row[0]]!;
        expect(t.name, row[1]);
        expect(t.population, row[2]);
        expect(t.area, row[3]);
        expect(t.neighbors, {for (final i in row[4]) ids[i as int]});
      }
      expect(
        (a.towns as CompactTowns).materializedCount,
        lessThanOrEqualTo(512),
      );
      final g = Game(a)..setHome('29205043001');
      g.selectAttackTarget('29205041001');
      g.tap('29205041001', DateTime.now());
      final restored = Game.restore(a, g.toJson());
      expect(restored.toJson(), g.toJson());
      final legacy = {
        'owned': ['29205043001'],
        'everOwned': ['29205043001'],
        'progress': {'29205041001': 7},
        'home': '29205043001',
      };
      await n.prepareLegacySave(legacy);
      expect(a.sourceTowns, isNotEmpty);
      final old = g.toJson()..remove('territoryUnit');
      old['progress'] = {'29205041001': 7};
      final migrated = Game.restore(a, old);
      expect(migrated.home, g.home);
      expect(migrated.progress['29205041001'], 7);
      n.releaseLegacySave();
      expect(a.sourceTowns, isEmpty);
      expect(a.membersByTown, isEmpty);
      await n.ensureGeometry('29');
      final town = a.towns['29205041001']!;
      expect(town.polygons, isNotEmpty);
      expect(identical(town, a.towns[town.id]), true);
      await n.releaseGeometry();
      expect(town.polygons, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

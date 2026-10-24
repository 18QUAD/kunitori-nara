import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NationalAtlas data;
  setUpAll(() async => data = await NationalAtlas.load());

  test(
    'every municipality has a marker; Nara quiz offices and saves stay intact',
    () {
      final atlas = data.atlas;
      expect(atlas.mapOffices.length, 1916);
      expect(atlas.mapOffices.keys.toSet(), containsAll(atlas.cities.keys));
      expect(atlas.offices.keys.toSet(), atlas.cities.keys.toSet());
      expect(atlas.officeTownIds.keys.toSet(), atlas.cities.keys.toSet());
      expect(atlas.towns.values.every((t) => t.polygons.isEmpty), isTrue);
      final original = jsonDecode(
        File('assets/data/nara_offices.json').readAsStringSync(),
      );
      for (final row in original['offices']) {
        final o = atlas.mapOffices[row['cityId']]!;
        expect(o.name, row['name']);
        expect([o.point.x, o.point.y], row['point']);
        expect(o.townId, atlas.sourceToTown[row['sourceTownId']]);
      }
      for (final o in atlas.mapOffices.values) {
        expect(atlas.cities.containsKey(o.cityId), isTrue);
        if (o.townId != null) expect(atlas.towns[o.townId]!.cityId, o.cityId);
      }
      expect(atlas.mapOffices['13101']!.isCity, isTrue);
      expect(atlas.mapOffices['14301']!.isCity, isFalse);
      expect(atlas.mapOffices['27127:city-hall']!.name, '大阪市役所');
      expect(atlas.mapOffices['27127']!.name, '大阪市北区役所');
      expect(atlas.mapOffices['47381']!.townId, isNull);
      final town = atlas.mapOffices['27127']!.townId!;
      final game = Game(atlas)..setHome(town);
      game.owned.addAll(atlas.byCity['27127']!.map((t) => t.id));
      expect(game.cityOwned('27127'), isTrue);
      expect(game.canStartQuizAt(town), isTrue);
      expect(game.canPracticeAt(town), isTrue);
      expect(
        game.tipsFor(selectedCity: '27127').where((f) => f.quizEligible).length,
        5,
      );
    },
  );

  dynamic painter(WidgetTester tester) {
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final box = (viewer.child as GestureDetector).child as SizedBox;
    return (((box.child as Stack).children.whereType<RepaintBoundary>().last)
                .child
            as CustomPaint)
        .painter;
  }

  testWidgets(
    'Osaka prefecture and ward maps expose city/ward office markers and selection',
    (tester) async {
      await tester.runAsync(() => data.ensureGeometry('27'));
      final game = Game(data.atlas)..setHome('29205043001');
      game.selectAttackTarget('29205041001');
      game.tap('29205041001', DateTime.utc(2026));
      final saved = game.toJson();
      String? city, selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder:
                  (context, setState) => TerritoryMap(
                    atlas: data.atlas,
                    game: game,
                    prefectureId: '27',
                    cityId: city,
                    selected: selected,
                    focusVersion: 0,
                    onCitySelected: (value) => setState(() => city = value),
                    onSelected: (value) => setState(() => selected = value),
                  ),
            ),
          ),
        ),
      );
      await tester.pump();
      dynamic p = painter(tester);
      expect(
        p.officePoints.length,
        74,
      ); // 72 ward/municipal offices + 2 city halls.
      final nodes = p.semanticsBuilder(const Size(1100, 1500)) as List;
      final ward = nodes.firstWhere(
        (n) => (n.properties.label as String).startsWith('大阪市北区役所'),
      );
      expect(
        nodes.any((n) => (n.properties.label as String).startsWith('大阪市役所')),
        isTrue,
      );
      ward.properties.onTap();
      await tester.pumpAndSettle();
      expect(city, '27127');
      expect(selected, data.atlas.mapOffices['27127']!.townId);
      p = painter(tester);
      final wardNodes = p.semanticsBuilder(const Size(1100, 1500)) as List;
      expect(wardNodes.length, 2);
      expect(
        wardNodes.every(
          (n) => (n.properties.label as String).startsWith('大阪市'),
        ),
        isTrue,
      );
      expect(game.toJson(), saved);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an island headquarters keeps its real position and selects its explicit conquest hub',
    (tester) async {
      await tester.runAsync(() => data.ensureGeometry('47'));
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerritoryMap(
              atlas: data.atlas,
              game: Game(data.atlas),
              prefectureId: '47',
              cityId: '47381',
              selected: null,
              focusVersion: 0,
              onCitySelected: (_) {},
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.pump();
      final p = painter(tester);
      final nodes = p.semanticsBuilder(const Size(1100, 1500)) as List;
      expect(nodes.length, 1);
      expect(nodes.single.properties.label, '竹富町役場');
      nodes.single.properties.onTap();
      await tester.pump();
      expect(selected, data.atlas.officeTownIds['47381']);
      expect(data.atlas.mapOffices['47381']!.townId, isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

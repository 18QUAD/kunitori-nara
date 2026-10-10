import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/map_view.dart';
import 'package:kunitori/save_store.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  late Atlas atlas;
  setUpAll(() {
    atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
  });

  test(
    'map saves coalesce without overwriting game progress; corrupt views fall back',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SaveStore(prefs);
      final game = Game(atlas)..setHome(atlas.officeTownIds['29205']!);
      final operations = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        operations.add(
          store.saveMapView(
            MapViewState(
              center: Offset(100 + i.toDouble(), 300),
              scale: 2,
              selected: null,
              cityId: null,
              showGeography: false,
            ),
          ),
        );
        operations.add(store.save(game));
      }
      await Future.wait(operations);
      expect(store.loadMapView(atlas)!.center, const Offset(119, 300));
      expect(store.load(atlas).toJson(), game.toJson());
      final valid = store.loadMapView(atlas)!.toJson();
      for (final invalid in [
        {...valid, 'scale': 0},
        {...valid, 'scale': 151},
        {
          ...valid,
          'center': ['bad', 0],
        },
        {...valid, 'selected': 'missing-town'},
        {...valid, 'cityId': 'missing-city'},
        {...valid, 'projection': 'old'},
      ]) {
        await prefs.setString(SaveStore.mapViewKey, jsonEncode(invalid));
        expect(store.loadMapView(atlas), isNull);
        expect(store.load(atlas).toJson(), game.toJson());
      }
      await prefs.setString(SaveStore.mapViewKey, '{broken');
      expect(store.loadMapView(atlas), isNull);
      expect(prefs.getString(SaveStore.mapViewKey), '{broken');
    },
  );

  testWidgets(
    'launch restores map; pan, zoom, overview and geography survive restart and resizing',
    (tester) async {
      final game = Game(atlas)..setHome(atlas.officeTownIds['29205']!);
      final selected = atlas.byCity['29212']!.first.id;
      final saved = MapViewState(
        center: const Offset(590, 830),
        scale: 1.5,
        selected: selected,
        cityId: '29212',
        showGeography: false,
      );
      SharedPreferences.setMockInitialValues({
        'flutter.${SaveStore.key}': jsonEncode(game.toJson()),
        'flutter.${SaveStore.mapViewKey}': jsonEncode(saved.toJson()),
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> launch() async {
        await tester.pumpWidget(const KunitoriApp());
        for (
          var i = 0;
          i < 30 && find.byType(TerritoryMap).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      void expectCamera(Offset center, double scale) {
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final viewport = tester.getSize(find.byType(TerritoryMap));
        final actual = viewer.transformationController!.toScene(
          Offset(viewport.width / 2, viewport.height / 2),
        );
        expect(actual.dx, closeTo(center.dx, 0.0001));
        expect(actual.dy, closeTo(center.dy, 0.0001));
        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(scale, 0.0001),
        );
      }

      await launch();
      // Check the rendered button surfaces rather than only theme configuration.
      final mapButtons = find.descendant(
        of: find.byType(TerritoryMap),
        matching: find.byType(IconButton),
      );
      expect(mapButtons, findsNWidgets(5));
      for (final button in mapButtons.evaluate()) {
        final surface = tester.widget<Material>(
          find.descendant(
            of: find.byWidget(button.widget),
            matching: find.byType(Material),
          ).first,
        );
        expect(surface.color, Colors.white);
      }
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).selected,
        selected,
      );
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).cityId,
        '29212',
      );
      expectCamera(saved.center, saved.scale);
      expect(find.byTooltip('起伏・市街地・山名・川・池・湖を表示'), findsOneWidget);

      await tester.tap(find.byTooltip('県全域を表示'));
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final size = tester.getSize(find.byType(TerritoryMap));
      const center = Offset(430, 620), scale = 2.2;
      viewer.transformationController!.value =
          Matrix4.identity()
            ..translate(
              size.width / 2 - center.dx * scale,
              size.height / 2 - center.dy * scale,
            )
            ..scale(scale);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final persisted = SaveStore(prefs).loadMapView(atlas)!;
      expect(persisted.cityId, isNull);
      expect(persisted.selected, isNull);
      expect(persisted.showGeography, isFalse);
      expect(persisted.scale, scale);
      expect(persisted.center.dx, closeTo(center.dx, 0.0001));

      await tester.pumpWidget(const SizedBox());
      await launch();
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).cityId,
        isNull,
      );
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).selected,
        isNull,
      );
      expectCamera(center, scale);
      tester.view.physicalSize = const Size(360, 720);
      await tester.pumpAndSettle();
      expectCamera(center, scale);
      expect(find.byTooltip('起伏・市街地・山名・川・池・湖を表示'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

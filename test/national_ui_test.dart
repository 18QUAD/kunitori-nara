import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/national_map.dart';
import 'package:kunitori/save_store.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  testWidgets(
    'real national and prefecture maps preserve a saved Nara campaign',
    (tester) async {
      final nara = Atlas.fromJson(
        jsonDecode(File('assets/data/nara.json').readAsStringSync()),
      );
      final home = nara.towns.values.firstWhere(
        (t) => t.neighbors.any((id) => nara.towns[id]!.population > 2),
      );
      final target = home.neighbors.firstWhere(
        (id) => nara.towns[id]!.population > 2,
      );
      final saved =
          Game(nara)
            ..setHome(home.id)
            ..selectAttackTarget(target);
      saved.tap(target, DateTime.now());
      SharedPreferences.setMockInitialValues({
        'flutter.${SaveStore.key}': jsonEncode(saved.toJson()),
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> waitForMap() async {
        for (var i = 0; i < 120; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          if (find.byType(TerritoryMap).evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();
        expect(find.byType(TerritoryMap), findsOneWidget);
      }

      await tester.pumpWidget(const KunitoriApp());
      await waitForMap();
      final game = tester.widget<TerritoryMap>(find.byType(TerritoryMap)).game;
      expect(game.progress[target], 1);
      await tester.tap(find.byKey(const Key('map-up')));
      await tester.pumpAndSettle();
      if (find.byType(NationalMap).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('map-up')));
        await tester.pumpAndSettle();
      }
      final national = tester.widget<NationalMap>(find.byType(NationalMap));
      expect(national.data.prefectures.length, 47);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      for (var attempt = 0; attempt < 100; attempt++) {
        if (find.text('起伏を読み込み中…').evaluate().isEmpty &&
            find.text('市街地を読み込み中…').evaluate().isEmpty &&
            find.text('川・湖を読み込み中…').evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('起伏を読み込み中…'), findsNothing);
      expect(find.text('起伏を読み込めませんでした · 再試行'), findsNothing);
      dynamic nationalPainter() {
        final current = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final box = (current.child as GestureDetector).child as SizedBox;
        return (((box.child as Stack).children.first as RepaintBoundary).child
                as CustomPaint)
            .painter;
      }

      Future<void> waitForTiles() async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          final semantics = tester.widget<Semantics>(
            find
                .descendant(
                  of: find.byType(GeographyTiles),
                  matching: find.byType(Semantics),
                )
                .first,
          );
          if (semantics.properties.label == '背景地図の読込完了') return;
        }
        fail('Background tile load did not complete');
      }

      await waitForTiles();
      Future<List<int>> hokkaidoPixel() async {
        final painter = nationalPainter();
        // The central Hokkaido mountains are far from borders and labels.
        const point = Offset(909, 195);
        expect((painter.paths['01'] as Path).contains(point), isTrue);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(1440, 1360));
        final tilePaint = tester.widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(GeographyTiles),
                matching: find.byType(CustomPaint),
              )
              .first,
        );
        final dynamic tilePainter = tilePaint.painter;
        canvas.save();
        canvas.translate(tilePainter.origin.dx, tilePainter.origin.dy);
        tilePainter.paint(canvas, const Size(1440, 1360));
        canvas.restore();
        final picture = recorder.endRecording();
        final result = await tester.runAsync(() async {
          final image = await picture.toImage(1440, 1360);
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final offset = (195 * 1440 + 909) * 4;
          final result = [
            for (var c = 0; c < 4; c++) data.getUint8(offset + c),
          ];
          image.dispose();
          return result;
        });
        picture.dispose();
        return result!;
      }

      final shaded = await hokkaidoPixel();
      final initialCamera = viewer.transformationController!.value.clone();
      await tester.tap(find.byTooltip('起伏・市街地・川・池・湖を非表示'));
      await tester.pumpAndSettle();
      final flat = await hokkaidoPixel();
      expect(flat, [0x43, 0x61, 0x6a, 255]);
      expect(shaded, isNot(flat));
      expect(shaded[3], 255);
      expect(viewer.transformationController!.value, initialCamera);
      final nationalPrefs = await SharedPreferences.getInstance();
      expect(
        SaveStore(
          nationalPrefs,
        ).loadMapView(national.data.atlas)!.showGeography,
        isFalse,
      );
      await tester.tap(find.byTooltip('起伏・市街地・川・池・湖を表示'));
      await tester.pumpAndSettle();
      expect(
        SaveStore(
          nationalPrefs,
        ).loadMapView(national.data.atlas)!.showGeography,
        isTrue,
      );
      final scale = viewer.transformationController!.value.getMaxScaleOnAxis();
      await tester.tap(find.byTooltip('拡大'));
      await tester.pumpAndSettle();
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(scale),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        SaveStore(prefs).loadMapView(national.data.atlas)!.nationalView,
        isTrue,
      );
      national.onPrefectureSelected('47');
      await tester.pump();
      await waitForMap();
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).prefectureId,
        '47',
      );
      expect(find.text('この地域の歴史・文化tipsは準備中です。'), findsOneWidget);
      expect(find.byIcon(Icons.terrain), findsOneWidget);
      expect(find.byIcon(Icons.terrain_outlined), findsNothing);
      for (var attempt = 0; attempt < 100; attempt++) {
        if (find.text('起伏を読み込み中…').evaluate().isEmpty &&
            find.text('市街地を読み込み中…').evaluate().isEmpty &&
            find.text('川・湖を読み込み中…').evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('起伏を読み込み中…'), findsNothing);
      expect(find.text('起伏を読み込めませんでした'), findsNothing);
      final prefectureViewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final camera = prefectureViewer.transformationController!.value.clone();
      await waitForTiles();
      final tilePaint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(GeographyTiles),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final dynamic tilePainter = tilePaint.painter;
      expect(tilePainter.tiles, isNotEmpty);
      await tester.tap(find.byTooltip('起伏・市街地・川・池・湖を非表示'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('起伏・市街地・川・池・湖を表示'), findsOneWidget);
      expect(prefectureViewer.transformationController!.value, camera);
      await tester.tap(find.byTooltip('起伏・市街地・川・池・湖を表示'));
      await tester.pumpAndSettle();
      final prefecture = tester.widget<TerritoryMap>(find.byType(TerritoryMap));
      final city = prefecture.atlas.cities.keys.firstWhere(
        (id) => id.startsWith('47'),
      );
      prefecture.onCitySelected(city);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).cityId,
        city,
      );
      await tester.tap(find.byKey(const Key('map-up')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).cityId,
        isNull,
      );
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).prefectureId,
        '47',
      );
      expect(find.byType(NationalMap), findsNothing);
      expect(game.home, saved.home);
      expect(game.owned, saved.owned);
      expect(game.progress, saved.progress);
      expect(game.totalTaps, saved.totalTaps);
      await tester.tap(find.byKey(const Key('map-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('map-home')));
      await tester.pumpAndSettle();
      final map = tester.widget<TerritoryMap>(find.byType(TerritoryMap));
      expect(map.prefectureId, '29');
      expect(map.selected, target);
      expect(game.progress[target], 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

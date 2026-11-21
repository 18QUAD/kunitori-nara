import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/map_view.dart';
import 'package:kunitori/national_atlas.dart';
import 'package:kunitori/save_store.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  late NationalAtlas data;
  late Map<String, dynamic> images;
  setUpAll(() async {
    data = await NationalAtlas.load();
    images = jsonDecode(
      File('data/prepared_maps/map-image-manifest.json').readAsStringSync(),
    );
  });

  Future<Game> launch(
    WidgetTester tester,
    String city, {
    bool seenGuide = false,
    bool attack = false,
    bool finishCity = false,
    bool legacyQuiz = false,
    bool unstarted = false,
  }) async {
    final atlas = data.atlas, hub = data.atlas.officeTownIds[city]!;
    final game = Game(atlas);
    if (!unstarted) game.startAt(hub);
    final target =
        attack
            ? atlas.byCity[city]!
                .firstWhere((t) => t.id != hub && game.canAttack(t.id))
                .id
            : hub;
    if (!attack && !unstarted) {
      game.owned.addAll(atlas.byCity[city]!.map((t) => t.id));
    }
    if (finishCity) {
      game.owned.addAll(
        atlas.byCity[city]!.where((t) => t.id != target).map((t) => t.id),
      );
      game.progress[target] = game.requiredTaps(atlas.towns[target]!) - 1;
    }
    game.everOwned.addAll(game.owned);
    final saved = game.toJson();
    if (legacyQuiz) {
      saved['quizRule'] = 'office-five-v1';
      saved['quiz'] = {
        'cityId': city,
        'correctCount': 2,
        'deadline': DateTime.utc(2000).toIso8601String(),
        'pausedRemainingMs': 7000,
      };
    }
    if (seenGuide) game.conquestGuideSeen.add(city);
    SharedPreferences.setMockInitialValues({
      'flutter.${SaveStore.key}': jsonEncode(saved),
      'flutter.${SaveStore.mapViewKey}': jsonEncode(
        MapViewState(
          center: const Offset(550, 750),
          scale: 1,
          selected: target,
          cityId: city,
          prefectureId: city.substring(0, 2),
          showGeography: false,
        ).toJson(),
      ),
    });
    // Keep real town/office geometry and the real capture UI. Tile pixels are not
    // under test: fill each encoded-image slot with a tiny decodable GIF.
    final gif = base64Decode(
      'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
    );
    final packs = {
      for (final p in images['packs']) 'data/prepared_maps/${p[0]}': p,
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final name = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      final pack = packs[name];
      if (pack != null) {
        final bytes = Uint8List(pack[2] as int);
        var offset = 0;
        for (var i = pack[3] as int; i < pack[4]; i++) {
          final length = images['assets'][i][1] as int;
          assert(length >= gif.length);
          bytes.setRange(offset, offset + gif.length, gif);
          offset += length;
        }
        return bytes.buffer.asByteData();
      }
      final direct = File(name), built = File('build/unit_test_assets/$name');
      final file = direct.existsSync() ? direct : built;
      return file.existsSync()
          ? file.readAsBytesSync().buffer.asByteData()
          : null;
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const KunitoriApp());
    for (
      var i = 0;
      i < 100 && find.byType(TerritoryMap).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(TerritoryMap), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    return tester.widget<TerritoryMap>(find.byType(TerritoryMap)).game;
  }

  testWidgets(
    'start has no fixed base and the map button is disabled before acquisition',
    (tester) async {
      final game = await launch(tester, '24216', unstarted: true);
      expect(game.hasStarted, isFalse);
      expect(
        tester.widget<IconButton>(find.byKey(const Key('map-home'))).onPressed,
        isNull,
      );
      expect(find.text('ここを本拠地にする'), findsNothing);
      await tester.tap(find.text('ここから攻略を始める').first);
      await tester.pump();
      expect(game.hasStarted, isTrue);
      expect(game.campaignFocusTownId, game.lastCapturedTownId);
      expect(game.toJson().containsKey('home'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'map button returns to latest capture, then prioritizes an ongoing attack',
    (tester) async {
      final game = await launch(tester, '24216', attack: true);
      TerritoryMap map() =>
          tester.widget<TerritoryMap>(find.byType(TerritoryMap));
      Future<void> pressMapButton() async {
        // Tile pixels are mocked in this fixture. Exercise the application's
        // supplied navigation button; decoding locks have separate coverage.
        final button =
            map().controls.singleWhere((w) => w.key == const Key('map-home'))
                as IconButton;
        expect(button.onPressed, isNotNull);
        button.onPressed!();
        await tester.pump();
      }

      final initial = game.lastCapturedTownId!;
      final target = map().selected!;
      game.progress[target] = game.requiredTaps(game.atlas.towns[target]!) - 1;
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('action-region')),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      await tester.pump();
      expect(game.lastCapturedTownId, target);
      map().onSelected(initial);
      await tester.pump();
      expect(map().selected, initial);
      expect(find.byTooltip('直前に攻略した地域へ'), findsOneWidget);
      await pressMapButton();
      expect(map().selected, target);
      final ongoing = game.atlas.towns[target]!.neighbors.firstWhere(
        (id) =>
            !game.owned.contains(id) && game.atlas.towns[id]!.population > 1,
      );
      map().onSelected(ongoing);
      game.tap(ongoing, DateTime.utc(2026));
      map().onSelected(initial);
      await tester.pump();
      expect(find.byTooltip('攻略中の地域へ'), findsOneWidget);
      await pressMapButton();
      expect(map().selected, ongoing);
      expect(game.lastCapturedTownId, target);
      final prefs = await SharedPreferences.getInstance();
      final restored = Game.restore(
        game.atlas,
        jsonDecode(prefs.getString(SaveStore.key)!),
      );
      expect(restored.lastCapturedTownId, target);
      expect(restored.attackTarget, ongoing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'map and old-name search use display names without conquest quiz actions',
    (tester) async {
      final game = await launch(tester, '26211');
      expect(
        tester.widget<Text>(find.byKey(const Key('current-location'))).data,
        '田辺',
      );
      expect(game.atlas.towns['26211010001']!.name, '田辺田辺');
      expect(game.mastered, contains('26211'));
      expect(game.quiz, isNull);
      expect(find.text('制圧クイズに挑戦'), findsNothing);
      expect(find.text('クイズを予習'), findsNothing);
      final beforeSettings = game.toJson();
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('戦績'), findsNothing);
      expect(find.text('戦績と足跡'), findsNothing);
      expect(find.text('最初からやり直す'), findsOneWidget);
      expect(game.toJson(), beforeSettings);
      await tester.tap(find.text('地名から探す'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '田辺田辺');
      await tester.pump();
      expect(find.widgetWithText(ListTile, '田辺'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '田辺田辺'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'last attack completes and saves a municipality without further input',
    (tester) async {
      final game = await launch(
        tester,
        '24216',
        attack: true,
        finishCity: true,
      );
      expect(game.mastered.contains('24216'), isFalse);
      final before = game.totalTaps;
      final panel = find.byKey(const Key('action-region'));
      await tester.tap(
        find.descendant(of: panel, matching: find.byType(FilledButton)).first,
      );
      await tester.pump();
      expect(game.totalTaps, before + 1);
      expect(game.mastered, contains('24216'));
      expect(game.quiz, isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('制圧クイズに挑戦'), findsNothing);
      expect(find.byKey(const Key('conquest-next')), findsNothing);
      expect(find.textContaining('完全制圧'), findsWidgets);
      final prefs = await SharedPreferences.getInstance();
      final restored = Game.restore(
        data.atlas,
        jsonDecode(prefs.getString(SaveStore.key)!),
      );
      expect(restored.mastered, contains('24216'));
      expect(restored.owned, game.owned);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'an old expired or paused conquest quiz resumes as complete control',
    (tester) async {
      final game = await launch(tester, '47381', legacyQuiz: true);
      expect(game.cityOwned('47381'), isTrue);
      expect(game.mastered, contains('47381'));
      expect(game.quiz, isNull);
      expect(game.losses, 0);
      expect(find.text('制圧クイズに挑戦'), findsNothing);
      expect(find.text('クイズを予習'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets(
    'landscape has one central map, two working attacks, and survives rotation',
    (tester) async {
      final game = await launch(tester, '24216', attack: true);
      final before = game.totalTaps;
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('landscape-play-layout')), findsOneWidget);
      expect(find.byType(TerritoryMap), findsOneWidget);
      final map = tester.getRect(find.byType(TerritoryMap));
      for (final name in ['landscape-left-action', 'landscape-right-action']) {
        final region = find.byKey(ValueKey(name));
        final button = find.descendant(
          of: region,
          matching: find.byType(FilledButton),
        );
        expect(button, findsOneWidget);
        final rect = tester.getRect(button);
        expect(rect.overlaps(map), isFalse);
        await tester.tapAt(tester.getCenter(region));
        await tester.pump();
      }
      expect(game.totalTaps, before + 2);
      expect(find.byTooltip('設定'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(667, 320);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(find.byKey(const Key('landscape-play-layout')), findsNothing);
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).game,
        same(game),
      );
      expect(game.totalTaps, before + 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/answer_feedback.dart';
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
  }) async {
    final atlas = data.atlas, hub = data.atlas.officeTownIds[city]!;
    final game = Game(atlas)..setHome(hub);
    game.owned.addAll(atlas.byCity[city]!.map((t) => t.id));
    game.everOwned.addAll(game.owned);
    if (seenGuide) game.conquestGuideSeen.add(city);
    SharedPreferences.setMockInitialValues({
      'flutter.${SaveStore.key}': jsonEncode(game.toJson()),
      'flutter.${SaveStore.mapViewKey}': jsonEncode(
        MapViewState(
          center: const Offset(550, 750),
          scale: 1,
          selected: hub,
          cityId: city,
          prefectureId: city.substring(0, 2),
          showGeography: false,
        ).toJson(),
      ),
    });
    // Keep real town/office geometry and the real quiz UI. Tile pixels are not
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
    'Iga starts from an existing fully owned save, shows the guide, and completes five answers',
    (tester) async {
      final game = await launch(tester, '24216');
      await tester.tap(find.text('制圧クイズに挑戦'));
      await tester.pump();
      for (var page = 0; page < 7; page++) {
        expect(find.byKey(const Key('conquest-next')), findsOneWidget);
        await tester.tap(find.byKey(const Key('conquest-next')));
        await tester.pump();
      }
      await tester.tap(find.text('役所へ移動して挑戦'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        expect(game.quiz, isNotNull);
        expect(find.byType(OutlinedButton), findsNWidgets(4));
        await tester.tap(
          find.widgetWithText(OutlinedButton, game.quiz!.answer),
        );
        await tester.pump();
        await tester.pump(answerFeedbackDisplayDuration);
        await tester.pump();
      }
      expect(game.mastered, contains('24216'));
      expect(game.cityOwned('24216'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      final restored = Game.restore(
        data.atlas,
        jsonDecode(prefs.getString(SaveStore.key)!),
      );
      expect(restored.mastered, contains('24216'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'Taketomi uses its in-territory hub and a wrong answer leaves other towns owned',
    (tester) async {
      final game = await launch(tester, '47381', seenGuide: true);
      final before = {...game.owned}, hub = data.atlas.officeTownIds['47381']!;
      await tester.tap(find.text('制圧クイズに挑戦'));
      await tester.pump();
      final q = game.quiz!;
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          q.choices.firstWhere((a) => a != q.answer),
        ),
      );
      await tester.pump();
      await tester.pump(answerFeedbackDisplayDuration);
      await tester.pump();
      expect(game.owned, before..remove(hub));
      expect(game.isReachable(hub), isTrue);
      expect(game.message, contains('制圧拠点'));
      expect(data.atlas.mapOffices['47381']!.townId, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

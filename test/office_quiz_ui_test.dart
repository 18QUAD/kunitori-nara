import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  testWidgets(
    'office map tap confirms, cancel preserves land, five answers clear',
    (tester) async {
      rootBundle.clear();
      final atlas = Atlas.fromJson(
        jsonDecode(File('assets/data/nara.json').readAsStringSync()),
      );
      final office = atlas.officeTownIds['29205']!;
      final saved = Game(atlas)..setHome(office);
      saved.owned.addAll(atlas.byCity['29205']!.map((t) => t.id));
      saved.everOwned.addAll(saved.owned);
      SharedPreferences.setMockInitialValues({
        'flutter.kunitori.nara.v1': jsonEncode(saved.toJson()),
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const KunitoriApp());
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        if (find.byType(TerritoryMap).evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      final map = tester.widget<TerritoryMap>(find.byType(TerritoryMap));
      final game = map.game;
      expect(game.owned, saved.owned);
      expect(game.quiz, isNull);
      Future<void> tapOffice() async {
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final dynamic painter =
            (((viewer.child as GestureDetector).child as SizedBox).child
                    as CustomPaint)
                .painter;
        final Offset point = painter.officePoints['29205'];
        final screen = MatrixUtils.transformPoint(
          viewer.transformationController!.value,
          point,
        );
        await tester.tapAt(
          tester.getTopLeft(find.byType(InteractiveViewer)) + screen,
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byTooltip('県全域を表示'));
      await tester.pumpAndSettle();
      await tapOffice();
      expect(
        tester.widget<TerritoryMap>(find.byType(TerritoryMap)).cityId,
        '29205',
      );
      expect(find.text('クイズを開始'), findsOneWidget);
      expect(game.quiz, isNull);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(game.quiz, isNull);
      expect(game.owned, saved.owned);
      expect(game.losses, 0);
      await tapOffice();
      await tester.tap(find.text('クイズを開始'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        expect(find.text('橿原市 · 制圧クイズ ${i + 1} / 5問'), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNWidgets(4));
        final answer = game.quiz!.answer;
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, answer));
        await tester.tap(find.widgetWithText(OutlinedButton, answer));
        await tester.pumpAndSettle();
      }
      expect(game.quiz, isNull);
      expect(game.mastered, contains('29205'));
      expect(game.wins, 1);
      expect(find.textContaining('5問全問正解！'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final restored = Game.restore(
        atlas,
        jsonDecode(prefs.getString('kunitori.nara.v1')!),
      );
      expect(restored.mastered, game.mastered);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

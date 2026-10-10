import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/answer_feedback.dart';
import 'package:kunitori/practice_quiz.dart';
import 'package:kunitori/quiz_prompt.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/territory_map.dart';
import 'package:kunitori/tip_presenter.dart';
import 'package:kunitori/tip_appearance.dart';
import 'package:kunitori/tip_character.dart';

void main() {
  testWidgets(
    'office practice unlocks after capture, keeps the full attack area before capture and preserves progress',
    (tester) async {
      rootBundle.clear();
      final atlas = Atlas.fromJson(
        jsonDecode(File('assets/data/nara.json').readAsStringSync()),
      );
      final office = atlas.officeTownIds['29205']!;
      final saved = Game(atlas)..setHome(atlas.towns[office]!.neighbors.first);
      saved.selectAttackTarget(office);
      saved.progress[office] = saved.requiredTaps(atlas.towns[office]!) - 1;
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
      expect(find.text('クイズを開始'), findsNothing);
      expect(find.text('クイズを予習'), findsNothing);
      final attackRect = tester.getRect(find.byKey(const Key('attack')));
      final actionRect = tester.getRect(find.byKey(const Key('action-region')));
      expect(attackRect.height, closeTo(actionRect.height - 16, .01));
      await tester.tap(find.byKey(const Key('attack')));
      await tester.pumpAndSettle();
      expect(game.owned, contains(office));
      expect(find.byKey(const Key('attack')), findsNothing);
      expect(find.text('クイズを予習'), findsOneWidget);
      final practiceRect = tester.getRect(
        find.ancestor(
          of: find.text('クイズを予習'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(practiceRect.top, greaterThanOrEqualTo(actionRect.top));
      expect(practiceRect.bottom, lessThanOrEqualTo(actionRect.bottom));
      final mapController =
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!;
      final mapTransform = mapController.value.clone();
      final before = jsonEncode(game.toJson());
      await tester.tap(find.text('クイズを予習'));
      await tester.pumpAndSettle();
      expect(find.text(PracticeQuizController.introduction), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('橿原市 · クイズ予習 全5問'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(jsonEncode(game.toJson()), before);
      await tester.tap(find.text('クイズを予習'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開始する'));
      await tester.pumpAndSettle();
      expect(find.textContaining('橿原市 · クイズ予習 1/5問'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(TerritoryMap), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      for (var i = 0; i < 5; i++) {
        final question =
            tester.widget<PracticeQuiz>(find.byType(PracticeQuiz)).questions[i];
        final answer =
            i == 0
                ? question.choices.firstWhere((a) => a != question.answer)
                : question.answer;
        expect(find.byType(QuizPrompt), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(QuizPrompt),
            matching: find.text(question.question),
          ),
          findsOneWidget,
        );
        final option = find.widgetWithText(OutlinedButton, answer);
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(find.textContaining(i == 0 ? '正解は「' : '答えは「'), findsOneWidget);
        expect(find.byType(AnswerFeedback), findsOneWidget);
        expect(
          tester.widget<AnswerFeedback>(find.byType(AnswerFeedback)).correct,
          i != 0,
        );
        final next = find.text(i == 4 ? '結果を見る' : '次の問題');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('おつかれさま！5問中4問正解だったよ'), findsOneWidget);
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController,
        same(mapController),
      );
      expect(mapController.value, mapTransform);
      expect(game.quiz, isNull);
      // The tips timer may record seen tips; practice must not change gameplay.
      final after = game.toJson()..['seen'] = jsonDecode(before)['seen'];
      expect(jsonEncode(after), before);
      await tester.tap(find.text('地図へ戻る'));
      await tester.pumpAndSettle();
      expect(find.text('クイズを予習'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
      final practiceRect = tester.getRect(
        find.ancestor(
          of: find.text('クイズを予習'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      final quizRect = tester.getRect(
        find.ancestor(
          of: find.text('制圧クイズに挑戦'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(practiceRect.overlaps(quizRect), isFalse);
      expect(find.byKey(const Key('attack')), findsNothing);
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
        expect(find.byType(TerritoryMap), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(
          tester.widget<TerritoryMap>(find.byType(TerritoryMap)).showControls,
          isFalse,
        );
        expect(find.text('クイズを予習'), findsNothing);
        expect(find.text('上の選択肢をタップして回答'), findsOneWidget);
        expect(find.text('制圧成功'), findsNothing);
        final prompt = find.byType(QuizPrompt);
        expect(prompt, findsOneWidget);
        expect(
          find.descendant(
            of: prompt,
            matching: find.byKey(const Key('tip-character')),
          ),
          findsOneWidget,
        );
        final text = tester.widget<Text>(
          find.descendant(
            of: prompt,
            matching: find.byKey(const Key('tip-text')),
          ),
        );
        expect(text.data, game.quiz!.question);
        expect(text.maxLines, isNull);
        final answer = game.quiz!.answer;
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, answer));
        final duplicateAnswer =
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, answer),
                )
                .onPressed!;
        await tester.tap(find.widgetWithText(OutlinedButton, answer));
        duplicateAnswer();
        await tester.pump();
        expect(find.byType(AnswerFeedback), findsOneWidget);
        expect(find.byType(TerritoryMap), findsOneWidget);
        expect(find.textContaining('正解！'), findsOneWidget);
        expect(
          find.text(['good！', 'nice！', 'great！', 'brilliant！', 'perfect！'][i]),
          findsOneWidget,
        );
        expect(game.quiz?.correctCount ?? 5, i + 1);
        await tester.pump(const Duration(milliseconds: 2500));
        expect(find.byType(AnswerFeedback), findsOneWidget);
        await tester.pump(
          answerFeedbackDisplayDuration - const Duration(milliseconds: 2500),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(AnswerFeedback),
          i == 4 ? findsOneWidget : findsNothing,
        );
      }
      expect(game.quiz, isNull);
      expect(game.mastered, contains('29205'));
      expect(game.wins, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('制圧完了'), findsOneWidget);
      expect(find.text('橿原市の制圧おめでとう！次の町を選んでね！'), findsOneWidget);
      final celebration = tester.widget<TipPresenter>(
        find.byType(TipPresenter),
      );
      expect(celebration.expression, TipExpression.joyful);
      expect(celebration.lipSyncDuration, const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('制圧完了'), findsNothing);
      expect(find.text('橿原市の制圧おめでとう！次の町を選んでね！'), findsOneWidget);
      expect(find.byType(TerritoryMap), findsOneWidget);
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
  testWidgets(
    'town conquest celebrates once and holds speech until another town is selected',
    (tester) async {
      rootBundle.clear();
      final atlas = Atlas.fromJson(
        jsonDecode(File('assets/data/nara.json').readAsStringSync()),
      );
      final home = atlas.officeTownIds['29205']!;
      final saved = Game(atlas)..setHome(home);
      final target = atlas.towns.values.firstWhere(
        (t) =>
            t.id != home &&
            t.neighbors.contains(home) &&
            !atlas.officeTownIds.values.contains(t.id),
      );
      saved.selectAttackTarget(target.id);
      saved.progress[target.id] = saved.requiredTaps(target) - 1;
      SharedPreferences.setMockInitialValues({
        'flutter.kunitori.nara.v1': jsonEncode(saved.toJson()),
      });
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
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final game = tester.widget<TerritoryMap>(find.byType(TerritoryMap)).game;
      await tester.tap(find.byKey(const Key('attack')));
      await tester.pump();
      expect(game.owned, contains(target.id));
      expect(find.text('制圧完了'), findsOneWidget);
      final speech = '${target.name}の制圧おめでとう！次の町を選んでね！';
      expect(find.text(speech), findsOneWidget);
      final presenter = tester.widget<TipPresenter>(find.byType(TipPresenter));
      expect(presenter.expression, TipExpression.joyful);
      expect(presenter.lipSyncDuration, const Duration(seconds: 3));
      final characterState = tester.state(find.byType(TipCharacterView));
      await tester.pump(const Duration(seconds: 4));
      expect(tester.state(find.byType(TipCharacterView)), same(characterState));
      expect(find.byKey(const Key('guide-closed-mouth')), findsOneWidget);
      final character = find.byType(TipCharacterView);
      final mouth = tester.widget<TipCharacterView>(character);
      expect(mouth.expression, TipExpression.joyful);
      expect(find.text('制圧完了'), findsNothing);
      final seen = {...game.seen};
      await tester.pump(const Duration(seconds: 20));
      expect(find.text(speech), findsOneWidget);
      expect(game.seen, seen);
      final next = atlas.towns.values.firstWhere(
        (t) =>
            game.isReachable(t.id) &&
            !game.owned.contains(t.id) &&
            !atlas.officeTownIds.values.contains(t.id),
      );
      tester
          .widget<TerritoryMap>(find.byType(TerritoryMap))
          .onSelected(next.id);
      await tester.pumpAndSettle();
      expect(find.text(speech), findsNothing);
      expect(
        tester.widget<TipPresenter>(find.byType(TipPresenter)).expression,
        TipExpression.neutral,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

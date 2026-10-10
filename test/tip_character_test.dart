import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/tip_appearance.dart';
import 'package:kunitori/tip_character.dart';
import 'package:kunitori/quiz_stage.dart';
import 'package:kunitori/game.dart';

void main() {
  Widget scene(
    TipAppearance a, {
    Object speech = 'one',
    DateTime? next,
    bool reduced = false,
    bool active = true,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: active,
        child: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: TipCharacterView(
              appearance: a,
              speechKey: speech,
              nextSpeechAt: next,
            ),
          ),
        ),
      ),
    ),
  );

  for (final character in TipCharacter.values) {
    testWidgets(
      '${character.name} changes expression for quiz results and resets on next question',
      (tester) async {
        const question = QuizQuestion(
          factId: 'expression',
          question: '問題',
          answer: '答え',
          choices: ['答え', '別の答え'],
        );
        for (final result in [null, true, false, null]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: QuizStage(
                  title: 'クイズ',
                  question: question,
                  correct: result,
                  streak: 1,
                  appearance: TipAppearance(
                    character: character,
                    blinkEnabled: false,
                  ),
                  onAnswer: (_) {},
                ),
              ),
            ),
          );
          final expected =
              result == null
                  ? TipExpression.neutral
                  : result
                  ? TipExpression.joyful
                  : TipExpression.disappointed;
          expect(
            tester
                .widget<TipCharacterView>(find.byType(TipCharacterView))
                .expression,
            expected,
          );
          if (character == TipCharacter.guide) {
            final names =
                tester
                    .widgetList<Image>(
                      find.descendant(
                        of: find.byType(TipCharacterView),
                        matching: find.byType(Image),
                      ),
                    )
                    .map((image) {
                      final provider =
                          image.image is ResizeImage
                              ? (image.image as ResizeImage).imageProvider
                              : image.image;
                      return (provider as AssetImage).assetName;
                    })
                    .toList();
            expect(
              names,
              contains(
                'assets/characters/nara_guide${result == null
                    ? ''
                    : result
                    ? '_joy'
                    : '_sad'}.png',
              ),
            );
          } else {
            expect(
              (tester
                          .widget<CustomPaint>(
                            find.byKey(const Key('deer-face-parts')),
                          )
                          .painter
                      as DeerCharacterPainter)
                  .expression,
              expected,
            );
          }
          await tester.pump(const Duration(milliseconds: 180));
          expect(
            tester
                .widget<TipCharacterView>(find.byType(TipCharacterView))
                .expression,
            expected,
          );
          await tester.pump(const Duration(seconds: 3));
          expect(
            tester
                .widget<TipCharacterView>(find.byType(TipCharacterView))
                .expression,
            expected,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final character in TipCharacter.values) {
    testWidgets(
      '${character.name} quiz speaks for three seconds per question despite countdown rebuilds',
      (tester) async {
        const first = QuizQuestion(
          factId: 'one',
          question: '問題1',
          answer: '答え',
          choices: ['答え'],
        );
        const second = QuizQuestion(
          factId: 'two',
          question: '問題2',
          answer: '答え',
          choices: ['答え'],
        );
        final next = DateTime.now().add(const Duration(seconds: 25));
        Widget quiz(QuizQuestion q, int seconds, {bool? result}) => MaterialApp(
          home: Scaffold(
            body: QuizStage(
              title: '予習・制圧共通',
              question: q,
              seconds: seconds,
              correct: result,
              nextSpeechAt: next,
              appearance: TipAppearance(
                character: character,
                blinkEnabled: false,
              ),
              onAnswer: (_) {},
            ),
          ),
        );
        bool closed() =>
            character == TipCharacter.guide
                ? find
                    .byKey(const Key('guide-closed-mouth'))
                    .evaluate()
                    .isNotEmpty
                : (tester
                            .widget<CustomPaint>(
                              find.byKey(const Key('deer-face-parts')),
                            )
                            .painter
                        as DeerCharacterPainter)
                    .mouthClosed;
        await tester.pumpWidget(quiz(first, 25));
        final initial = closed();
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), !initial);
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), initial);
        await tester.pump(const Duration(milliseconds: 2400));
        await tester.pumpWidget(quiz(first, 22));
        await tester.pump(const Duration(milliseconds: 300));
        expect(closed(), isTrue);
        await tester.pumpWidget(quiz(first, 20));
        await tester.pump(const Duration(milliseconds: 360));
        expect(closed(), isTrue);
        await tester.pumpWidget(quiz(second, 25));
        final restarted = closed();
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), !restarted);
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), restarted);
        await tester.pump(const Duration(milliseconds: 2700));
        expect(closed(), isTrue);
        for (final result in [true, false]) {
          await tester.pumpWidget(quiz(first, 0, result: result));
          final initialResult = closed();
          await tester.pump(const Duration(milliseconds: 180));
          expect(closed(), !initialResult);
          await tester.pump(const Duration(milliseconds: 180));
          expect(closed(), initialResult);
          await tester.pump(const Duration(milliseconds: 2700));
          expect(closed(), isTrue);
          await tester.pump(const Duration(milliseconds: 360));
          expect(closed(), isTrue);
        }
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${character.name} lip sync repeats and stops one second before next speech',
      (tester) async {
        final a = TipAppearance(character: character, blinkEnabled: false);
        final next = DateTime.now().add(const Duration(seconds: 5));
        bool closed() =>
            character == TipCharacter.guide
                ? find
                    .byKey(const Key('guide-closed-mouth'))
                    .evaluate()
                    .isNotEmpty
                : (tester
                            .widget<CustomPaint>(
                              find.byKey(const Key('deer-face-parts')),
                            )
                            .painter
                        as DeerCharacterPainter)
                    .mouthClosed;
        await tester.pumpWidget(scene(a, next: next));
        final initial = closed();
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), !initial);
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), initial);
        await tester.pump(const Duration(milliseconds: 3800));
        expect(closed(), isTrue);
        await tester.pump(const Duration(seconds: 2));
        expect(closed(), isTrue);
        await tester.pumpWidget(
          scene(
            a,
            speech: 'two',
            next: DateTime.now().add(const Duration(seconds: 5)),
          ),
        );
        final restarted = closed();
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), !restarted);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${character.name} blinks, then opens eyes; disabling animations cancels parts',
      (tester) async {
        final a = TipAppearance(character: character, lipSyncEnabled: false);
        bool closed() =>
            character == TipCharacter.guide
                ? find
                    .byKey(const Key('guide-closed-eyes'))
                    .evaluate()
                    .isNotEmpty
                : (tester
                            .widget<CustomPaint>(
                              find.byKey(const Key('deer-face-parts')),
                            )
                            .painter
                        as DeerCharacterPainter)
                    .eyesClosed;
        await tester.pumpWidget(scene(a));
        var blinked = false;
        for (var i = 0; i < 610; i++) {
          if (i % 50 == 0) {
            await tester.pumpWidget(scene(a, speech: i));
          }
          await tester.pump(const Duration(milliseconds: 10));
          if (closed()) {
            blinked = true;
            break;
          }
        }
        expect(blinked, isTrue);
        await tester.pump(const Duration(milliseconds: 140));
        expect(closed(), isFalse);
        await tester.pumpWidget(
          scene(a.copyWith(blinkEnabled: false, lipSyncEnabled: false)),
        );
        await tester.pump(const Duration(seconds: 10));
        expect(closed(), isFalse);
        await tester.pumpWidget(scene(a, reduced: true));
        await tester.pump(const Duration(seconds: 10));
        expect(closed(), isFalse);
        await tester.pumpWidget(scene(a, active: false));
        await tester.pump(const Duration(seconds: 10));
        expect(closed(), isFalse);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}

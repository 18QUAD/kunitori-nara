import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/answer_feedback.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/practice_quiz.dart';
import 'package:kunitori/quiz_stage.dart';

void main() {
  testWidgets('effects follow all five streak levels and wrong answer', (
    tester,
  ) async {
    final labels = [
      'good！',
      'nice！',
      'great！',
      'brilliant！',
      'perfect！',
      'bad',
    ];
    for (var i = 0; i < labels.length; i++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerFeedback(
              key: ValueKey(i),
              correct: i < 5,
              streak: i + 1,
            ),
          ),
        ),
      );
      expect(find.text(labels[i]), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion feedback stays still', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: AnswerFeedback(correct: false)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    for (final transform in tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(AnswerFeedback),
        matching: find.byType(Transform),
      ),
    )) {
      expect(transform.transform, Matrix4.identity());
    }
    await tester.pumpAndSettle();
  });

  const question = QuizQuestion(
    factId: 'test',
    question: '奈良県の県庁所在地はどこですか？',
    answer: '奈良市',
    choices: ['奈良市', '大阪市', '京都市', '鹿の王国'],
  );

  testWidgets(
    'small phone places options/effects above question/result bubble',
    (tester) async {
      tester.view.physicalSize = const Size(360, 528);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final correct in [null, true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 340,
                child: QuizStage(
                  title: '制圧クイズ 1 / 5問',
                  question: question,
                  correct: correct,
                  streak: 1,
                  onAnswer: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bubble = tester.getRect(find.byKey(const Key('tips-region')));
        final upper = tester.getRect(
          find.byKey(const Key('quiz-upper-region')),
        );
        expect(upper.bottom, lessThanOrEqualTo(bubble.top));
        if (correct == null) {
          expect(find.text(question.question), findsOneWidget);
          expect(find.byIcon(Icons.circle_outlined), findsNothing);
          expect(find.byIcon(Icons.close), findsNothing);
          expect(find.byType(OutlinedButton), findsNWidgets(4));
        } else {
          expect(
            find.textContaining(correct ? '答えは「奈良市」だよ' : '正解は「奈良市」だよ'),
            findsOneWidget,
          );
          expect(find.byType(OutlinedButton), findsNWidgets(4));
          expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
          expect(find.byIcon(Icons.close), findsNWidgets(3));
          for (final button in tester.widgetList<OutlinedButton>(
            find.byType(OutlinedButton),
          )) {
            expect(button.onPressed, isNull);
          }
          expect(
            find.descendant(
              of: find.widgetWithText(OutlinedButton, question.answer),
              matching: find.byIcon(Icons.circle_outlined),
            ),
            findsOneWidget,
          );
          expect(
            tester.getRect(find.byType(AnswerFeedback)).bottom,
            lessThanOrEqualTo(bubble.top),
          );
        }
        for (var option = 0; option < 4; option++) {
          expect(
            tester.getRect(find.byType(OutlinedButton).at(option)).bottom,
            lessThan(bubble.top),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('practice introduction fits all four choices on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 528);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PracticeQuizController([question]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 340,
            child: PracticeQuiz(
              cityName: '宇陀市',
              questions: [question],
              controller: controller,
              inline: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text(PracticeQuizController.introduction), findsOneWidget);
    expect(find.text(question.question), findsNothing);
    expect(find.text('宇陀市 · クイズ予習 全1問'), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(OutlinedButton), findsNothing);
    controller.start();
    await tester.pump();
    final title = tester.widget<Text>(find.text('宇陀市 · クイズ予習 1/1問'));
    expect(title.maxLines, 1);
    final bubble = tester.getRect(find.byKey(const Key('tips-region')));
    final upper = tester.getRect(find.byKey(const Key('quiz-upper-region')));
    for (var i = 0; i < 4; i++) {
      final rect = tester.getRect(find.byType(OutlinedButton).at(i));
      expect(rect.bottom, lessThanOrEqualTo(upper.bottom));
      expect(rect.bottom, lessThan(bubble.top));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('practice can be cancelled without starting', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PracticeQuiz(cityName: '奈良市', questions: [question]),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'practice resets streak after a wrong answer and blocks duplicate answers',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PracticeQuiz(
            cityName: '奈良市',
            questions: List.filled(4, question),
          ),
        ),
      );
      expect(find.text(PracticeQuizController.introduction), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('奈良市 · クイズ予習 全4問'), findsOneWidget);
      expect(find.text('やめる'), findsOneWidget);
      await tester.tap(find.text('開始する'));
      await tester.pump();
      expect(find.text(PracticeQuizController.introduction), findsNothing);
      for (var i = 0; i < 4; i++) {
        final answer = i == 2 ? '大阪市' : '奈良市';
        final callback =
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, answer),
                )
                .onPressed!;
        await tester.tap(find.widgetWithText(OutlinedButton, answer));
        callback();
        await tester.pumpAndSettle();
        expect(
          find.text(['good！', 'nice！', 'bad', 'good！'][i]),
          findsOneWidget,
        );
        await tester.tap(find.text(i == 3 ? '結果を見る' : '次の問題'));
        await tester.pumpAndSettle();
      }
      expect(find.text('おつかれさま！4問中3問正解だったよ。また一緒に予習しようね！'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

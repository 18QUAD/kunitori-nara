import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/action_choices.dart';
import 'package:kunitori/action_button_style.dart';
import 'package:kunitori/practice_quiz.dart';
import 'package:kunitori/game.dart';

void main() {
  testWidgets(
    'landscape practice choices occupy opposite panels and remain independent',
    (tester) async {
      final controller = PracticeQuizController([
        const QuizQuestion(
          factId: 'test',
          question: 'question',
          answer: 'yes',
          choices: ['yes', 'no'],
        ),
      ]);
      addTearDown(controller.dispose);
      var closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 844,
            height: 390,
            child: Row(
              children: [
                for (final right in [false, true]) ...[
                  if (right) const Expanded(flex: 56, child: SizedBox()),
                  Expanded(
                    flex: 22,
                    child: SizedBox(
                      height: 104,
                      child: ActionChoiceRegion(
                        right: right,
                        child: PracticeQuizControls(
                          controller: controller,
                          onClose: () => closes++,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      expect(find.text('やめる'), findsOneWidget);
      expect(find.text('開始する'), findsOneWidget);
      final left = tester.getRect(find.widgetWithText(FilledButton, 'やめる'));
      final right = tester.getRect(find.widgetWithText(FilledButton, '開始する'));
      expect(left.right, lessThan(right.left));
      expect(left.width, closeTo(right.width, .01));
      expect(left.width, greaterThan(150));
      expect(left.top, right.top);
      for (final button in tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      )) {
        expect(button.style!.shape!.resolve({}), actionButtonShape);
      }
      await tester.tap(find.text('開始する'));
      await tester.pump();
      expect(controller.introducing, false);
      expect(closes, 0);
      expect(find.byType(FilledButton), findsOneWidget);
      controller.answer('yes');
      await tester.pump();
      expect(find.text('結果を見る'), findsOneWidget);
      expect(tester.getRect(find.widgetWithText(FilledButton, '結果を見る')), right);
      await tester.tap(find.text('結果を見る'));
      await tester.pump();
      expect(controller.finished, true);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.text('地図へ戻る'));
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('portrait keeps both choices in one row', (tester) async {
    final controller = PracticeQuizController(const []);
    addTearDown(controller.dispose);
    // Generic choices also cover pause confirmation and conquest actions.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 366,
            height: 104,
            child: ActionChoices(
              children: [
                FilledButton(onPressed: () {}, child: const Text('はい')),
                FilledButton(onPressed: () {}, child: const Text('いいえ')),
              ],
            ),
          ),
        ),
      ),
    );
    final left = tester.getRect(find.widgetWithText(FilledButton, 'はい'));
    final right = tester.getRect(find.widgetWithText(FilledButton, 'いいえ'));
    expect(left.width, right.width);
    expect(right.left - left.right, 8);
    expect(left.top, right.top);
    expect(tester.takeException(), isNull);
  });
}

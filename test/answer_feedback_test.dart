import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/answer_feedback.dart';

void main() {
  for (final correct in [true, false]) {
    testWidgets('feedback shows result and answer: $correct', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AnswerFeedback(correct: correct, answer: '吉野杉')),
        ),
      );
      expect(find.text(correct ? '正解！' : '不正解'), findsOneWidget);
      expect(
        find.byIcon(
          correct ? Icons.check_circle_outline : Icons.cancel_outlined,
        ),
        findsOneWidget,
      );
      expect(find.text('正解は「吉野杉」'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(AnswerFeedback), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'reduced motion feedback stays still and dismisses automatically',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder:
                              (_) => const MediaQuery(
                                data: MediaQueryData(disableAnimations: true),
                                child: AnswerFeedback(
                                  correct: false,
                                  answer: '松',
                                  autoDismiss: true,
                                ),
                              ),
                        ),
                    child: const Text('回答'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('回答'));
      await tester.pump();
      expect(find.text('不正解'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(AnswerFeedback),
          matching: find.byType(Transform),
        ),
      );
      for (final transform in transforms) {
        expect(transform.transform, Matrix4.identity());
      }
      await tester.pumpAndSettle();
      expect(find.byType(AnswerFeedback), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'tip_appearance.dart';
import 'tip_presenter.dart';

class QuizPrompt extends StatelessWidget {
  const QuizPrompt({
    super.key,
    required this.question,
    this.appearance = const TipAppearance(),
    this.speechKey,
    this.nextSpeechAt,
    this.lipSyncDuration,
    this.expression = TipExpression.neutral,
  });
  final String question;
  final TipAppearance appearance;
  final Object? speechKey;
  final DateTime? nextSpeechAt;
  final Duration? lipSyncDuration;
  final TipExpression expression;

  @override
  Widget build(BuildContext context) => TipPresenter(
    key: const Key('quiz-question'),
    text: question,
    expandForText: true,
    speechKey: speechKey,
    nextSpeechAt: nextSpeechAt,
    lipSyncDuration: lipSyncDuration,
    expression: expression,
    appearance: appearance.copyWith(
      showTips: true,
      showCharacter: true,
      showBubble: true,
      bubbleShape: TipBubbleShape.speech,
      size: TipSize.large,
    ),
  );
}

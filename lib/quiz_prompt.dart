import 'package:flutter/material.dart';
import 'tip_appearance.dart';
import 'tip_presenter.dart';

class QuizPrompt extends StatelessWidget {
  const QuizPrompt({
    super.key,
    required this.question,
    this.appearance = const TipAppearance(),
  });
  final String question;
  final TipAppearance appearance;

  @override
  Widget build(BuildContext context) => TipPresenter(
    key: const Key('quiz-question'),
    text: question,
    expandForText: true,
    appearance: appearance.copyWith(
      showTips: true,
      showCharacter: true,
      showBubble: true,
      bubbleShape: TipBubbleShape.speech,
      size: TipSize.large,
    ),
  );
}

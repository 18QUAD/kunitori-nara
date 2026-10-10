import 'package:flutter/material.dart';
import 'answer_feedback.dart';
import 'game.dart';
import 'quiz_prompt.dart';
import 'tip_appearance.dart';

/// Options and effects occupy the map area above the guide's speech bubble.
class QuizStage extends StatelessWidget {
  const QuizStage({
    super.key,
    required this.title,
    required this.question,
    required this.onAnswer,
    this.appearance = const TipAppearance(),
    this.seconds,
    this.correct,
    this.streak = 0,
    this.nextSpeechAt,
  });

  final String title;
  final QuizQuestion question;
  final ValueChanged<String> onAnswer;
  final TipAppearance appearance;
  final int? seconds;
  final bool? correct;
  final int streak;
  final DateTime? nextSpeechAt;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: Column(
      children: [
        Expanded(
          child: Padding(
            key: const Key('quiz-upper-region'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      QuizTitle(
                        title: title,
                        seconds: correct == null ? seconds : null,
                      ),
                      const SizedBox(height: 8),
                      for (final answer in question.choices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: OutlinedButton(
                            onPressed:
                                correct == null ? () => onAnswer(answer) : null,
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              minimumSize: const Size.fromHeight(42),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              backgroundColor: const Color(
                                0xFF192A3A,
                              ).withValues(alpha: 0.8),
                              disabledBackgroundColor: const Color(
                                0xFF192A3A,
                              ).withValues(alpha: 0.8),
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white,
                              side:
                                  correct == null
                                      ? null
                                      : BorderSide(
                                        color:
                                            answer == question.answer
                                                ? const Color(0xFF7AE1BB)
                                                : const Color(0xFFFF8080),
                                      ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      correct == null
                                          ? null
                                          : Icon(
                                            answer == question.answer
                                                ? Icons.circle_outlined
                                                : Icons.close,
                                            color:
                                                answer == question.answer
                                                    ? const Color(0xFF7AE1BB)
                                                    : const Color(0xFFFF8080),
                                            semanticLabel:
                                                answer == question.answer
                                                    ? '正解'
                                                    : '不正解',
                                          ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(answer)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (correct != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnswerFeedback(
                            key: ValueKey(
                              '${question.factId}-$streak-$correct',
                            ),
                            correct: correct!,
                            streak: streak,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 8),
          child: Semantics(
            liveRegion: correct != null,
            child: QuizPrompt(
              question:
                  correct == null
                      ? question.question
                      : correct!
                      ? correctAnswerSpeech(question.answer, streak)
                      : '惜しい、今回は不正解！正解は「${question.answer}」だよ。',
              appearance: appearance,
              expression:
                  correct == null
                      ? TipExpression.neutral
                      : correct!
                      ? TipExpression.joyful
                      : TipExpression.disappointed,
              nextSpeechAt: nextSpeechAt,
              lipSyncDuration: const Duration(seconds: 3),
              speechKey: '${question.factId}:$correct',
            ),
          ),
        ),
      ],
    ),
  );
}

/// The same compact heading is shown before starting and during questions.
class QuizTitle extends StatelessWidget {
  const QuizTitle({super.key, required this.title, this.seconds});
  final String title;
  final int? seconds;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF101C2B).withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (seconds != null)
          Text(
            '残り $seconds 秒',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: seconds! <= 5 ? Colors.redAccent : const Color(0xFF7AE1BB),
            ),
          ),
      ],
    ),
  );
}

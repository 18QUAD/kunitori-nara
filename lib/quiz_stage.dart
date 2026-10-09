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
    child: ColoredBox(
      color: const Color(0xFF122B32),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              key: const Key('quiz-upper-region'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child:
                  correct != null
                      ? Center(
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
                      )
                      : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (seconds != null)
                              Text(
                                '残り $seconds 秒',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color:
                                      seconds! <= 5
                                          ? Colors.redAccent
                                          : const Color(0xFF7AE1BB),
                                ),
                              ),
                            const SizedBox(height: 8),
                            for (final answer in question.choices)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: OutlinedButton(
                                  onPressed: () => onAnswer(answer),
                                  style: OutlinedButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    minimumSize: const Size.fromHeight(42),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    backgroundColor: const Color(0xFF192A3A),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(answer),
                                ),
                              ),
                          ],
                        ),
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
                        : '${correct! ? '正解！' : '不正解'}\n正解は「${question.answer}」',
                appearance: appearance,
                nextSpeechAt: nextSpeechAt,
                speechKey: '${question.factId}:$correct',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

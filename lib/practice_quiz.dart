import 'package:flutter/material.dart';
import 'game.dart';
import 'answer_feedback.dart';

class PracticeQuiz extends StatefulWidget {
  const PracticeQuiz({
    super.key,
    required this.cityName,
    required this.questions,
  });
  final String cityName;
  final List<QuizQuestion> questions;

  @override
  State<PracticeQuiz> createState() => _PracticeQuizState();
}

class _PracticeQuizState extends State<PracticeQuiz> {
  int index = 0, correctCount = 0;
  String? choice;

  @override
  Widget build(BuildContext context) {
    final finished = index == widget.questions.length;
    final q = finished ? null : widget.questions[index];
    return AlertDialog(
      scrollable: true,
      title: Text('${widget.cityName} · クイズ予習'),
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('時間制限なし。領土・戦績には影響しません。'),
            const SizedBox(height: 16),
            if (finished)
              Text('予習完了！ $correctCount / ${widget.questions.length}問正解')
            else ...[
              Text('${index + 1} / ${widget.questions.length}問'),
              const SizedBox(height: 12),
              Text(q!.question, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              for (final answer in q.choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed:
                        choice != null
                            ? null
                            : () => setState(() {
                              choice = answer;
                              if (answer == q.answer) correctCount++;
                            }),
                    child: Text(answer),
                  ),
                ),
              if (choice != null)
                AnswerFeedback(
                  key: ValueKey(index),
                  correct: choice == q.answer,
                  answer: q.answer,
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(finished ? '地図へ戻る' : '予習を終了'),
        ),
        if (!finished && choice != null)
          FilledButton(
            onPressed:
                () => setState(() {
                  index++;
                  choice = null;
                }),
            child: Text(
              index + 1 == widget.questions.length ? '結果を見る' : '次の問題',
            ),
          ),
      ],
    );
  }
}

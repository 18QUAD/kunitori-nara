import 'package:flutter/material.dart';
import 'game.dart';
import 'quiz_stage.dart';
import 'tip_appearance.dart';

class PracticeQuiz extends StatefulWidget {
  const PracticeQuiz({
    super.key,
    required this.cityName,
    required this.questions,
    this.appearance = const TipAppearance(),
  });
  final String cityName;
  final TipAppearance appearance;
  final List<QuizQuestion> questions;

  @override
  State<PracticeQuiz> createState() => _PracticeQuizState();
}

class _PracticeQuizState extends State<PracticeQuiz> {
  int index = 0, correctCount = 0, streak = 0;
  String? choice;

  @override
  Widget build(BuildContext context) {
    final finished = index == widget.questions.length;
    final q = finished ? null : widget.questions[index];
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.cityName} · クイズ予習')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('時間制限なし。領土・戦績には影響しません。'),
                  ),
                  Expanded(
                    child:
                        finished
                            ? Center(
                              child: Text(
                                '予習完了！ $correctCount / ${widget.questions.length}問正解',
                              ),
                            )
                            : QuizStage(
                              title:
                                  '${index + 1} / ${widget.questions.length}問',
                              question: q!,
                              appearance: widget.appearance,
                              correct:
                                  choice == null ? null : choice == q.answer,
                              streak: streak,
                              onAnswer: (answer) {
                                if (choice != null) return;
                                setState(() {
                                  choice = answer;
                                  if (answer == q.answer) {
                                    correctCount++;
                                    streak++;
                                  } else {
                                    streak = 0;
                                  }
                                });
                              },
                            ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: OverflowBar(
                      children: [
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
                              index + 1 == widget.questions.length
                                  ? '結果を見る'
                                  : '次の問題',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

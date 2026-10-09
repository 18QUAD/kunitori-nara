import 'package:flutter/material.dart';
import 'game.dart';
import 'quiz_stage.dart';
import 'quiz_prompt.dart';
import 'tip_appearance.dart';

class PracticeQuizController extends ChangeNotifier {
  PracticeQuizController(this.questions);
  final List<QuizQuestion> questions;
  int index = 0, correctCount = 0, streak = 0;
  String? choice;
  bool get finished => index == questions.length;
  QuizQuestion get question => questions[index];
  bool? get correct => choice == null ? null : choice == question.answer;

  void answer(String value) {
    if (finished || choice != null) return;
    choice = value;
    if (value == question.answer) {
      correctCount++;
      streak++;
    } else {
      streak = 0;
    }
    notifyListeners();
  }

  void advance() {
    if (finished || choice == null) return;
    index++;
    choice = null;
    notifyListeners();
  }
}

class PracticeQuiz extends StatefulWidget {
  const PracticeQuiz({
    super.key,
    required this.cityName,
    required this.questions,
    this.appearance = const TipAppearance(),
    this.controller,
    this.inline = false,
    this.onClose,
  });
  final String cityName;
  final TipAppearance appearance;
  final List<QuizQuestion> questions;
  final PracticeQuizController? controller;
  final bool inline;
  final VoidCallback? onClose;

  @override
  State<PracticeQuiz> createState() => _PracticeQuizState();
}

class _PracticeQuizState extends State<PracticeQuiz> {
  late final controller =
      widget.controller ?? PracticeQuizController(widget.questions);
  void close() =>
      widget.onClose != null ? widget.onClose!() : Navigator.pop(context);

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  Widget stage() => ListenableBuilder(
    listenable: controller,
    builder:
        (context, _) =>
            controller.finished
                ? Column(
                  children: [
                    const Expanded(
                      child: Center(
                        child: Icon(
                          Icons.school_outlined,
                          size: 64,
                          color: Color(0xFF7AE1BB),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 8),
                      child: QuizPrompt(
                        question:
                            '予習完了！ ${controller.correctCount} / ${controller.questions.length}問正解',
                        appearance: widget.appearance,
                        lipSyncDuration: const Duration(seconds: 3),
                      ),
                    ),
                  ],
                )
                : QuizStage(
                  title:
                      '${widget.cityName} · クイズ予習\n${controller.index + 1} / ${controller.questions.length}問',
                  question: controller.question,
                  appearance: widget.appearance,
                  correct: controller.correct,
                  streak: controller.streak,
                  onAnswer: controller.answer,
                ),
  );

  @override
  Widget build(BuildContext context) =>
      widget.inline
          ? stage()
          : Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(child: stage()),
                  PracticeQuizControls(controller: controller, onClose: close),
                ],
              ),
            ),
          );
}

class PracticeQuizControls extends StatelessWidget {
  const PracticeQuizControls({
    super.key,
    required this.controller,
    required this.onClose,
  });
  final PracticeQuizController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder:
        (context, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '時間制限なし。領土・戦績には影響しません。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            OverflowBar(
              alignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: onClose,
                  child: Text(controller.finished ? '地図へ戻る' : '予習を終了'),
                ),
                if (!controller.finished && controller.choice != null)
                  FilledButton(
                    onPressed: controller.advance,
                    child: Text(
                      controller.index + 1 == controller.questions.length
                          ? '結果を見る'
                          : '次の問題',
                    ),
                  ),
              ],
            ),
          ],
        ),
  );
}

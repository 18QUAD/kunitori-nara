import 'package:flutter/material.dart';
import 'game.dart';
import 'quiz_stage.dart';
import 'quiz_prompt.dart';
import 'tip_appearance.dart';

class PracticeQuizController extends ChangeNotifier {
  PracticeQuizController(this.questions);
  static const introduction = '時間制限はないよ。領土や戦績も変わらないから、気軽に予習してみよう！';
  bool introducing = true;
  final List<QuizQuestion> questions;
  int index = 0, correctCount = 0, streak = 0;
  String? choice;
  bool get finished => index == questions.length;
  QuizQuestion get question => questions[index];
  bool? get correct => choice == null ? null : choice == question.answer;

  void answer(String value) {
    if (introducing || finished || choice != null) return;
    choice = value;
    if (value == question.answer) {
      correctCount++;
      streak++;
    } else {
      streak = 0;
    }
    notifyListeners();
  }

  void start() {
    if (!introducing || finished) return;
    introducing = false;
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
                : controller.introducing
                ? Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: QuizTitle(
                            title:
                                '${widget.cityName} · クイズ予習 全${controller.questions.length}問',
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 8),
                      child: QuizPrompt(
                        question: PracticeQuizController.introduction,
                        appearance: widget.appearance,
                        lipSyncDuration: const Duration(seconds: 3),
                        speechKey: 'practice-introduction',
                      ),
                    ),
                  ],
                )
                : QuizStage(
                  title:
                      '${widget.cityName} · クイズ予習 ${controller.index + 1}/${controller.questions.length}問',
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
            OverflowBar(
              alignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: onClose,
                  child: Text(
                    controller.finished
                        ? '地図へ戻る'
                        : controller.introducing
                        ? 'やめる'
                        : '予習を終了',
                  ),
                ),
                if (controller.introducing && !controller.finished)
                  FilledButton(
                    onPressed: controller.start,
                    child: const Text('開始する'),
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

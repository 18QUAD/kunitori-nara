import 'dart:math' as math;
import 'package:flutter/material.dart';

const answerFeedbackDuration = Duration(milliseconds: 850);
const answerFeedbackDisplayDuration = Duration(seconds: 3);

/// Shared answer feedback for practice and conquest, with bounded motion.
class AnswerFeedback extends StatelessWidget {
  const AnswerFeedback({super.key, required this.correct, this.streak = 1});

  final bool correct;
  final int streak;

  String get label =>
      correct
          ? [
            'good！',
            'nice！',
            'great！',
            'brilliant！',
            'perfect！',
          ][(streak.clamp(1, 5)) - 1]
          : 'bad';

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final color = correct ? const Color(0xFF7AE1BB) : const Color(0xFFFF8080);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: answerFeedbackDuration,
      builder: (context, progress, child) {
        final scale =
            reducedMotion || !correct
                ? 1.0
                : 0.75 +
                    Curves.easeOutBack.transform(
                          (progress * 3).clamp(0.0, 1.0),
                        ) *
                        0.25;
        final shake =
            reducedMotion || correct
                ? 0.0
                : math.sin(progress * math.pi * 6) * (1 - progress) * 10;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Semantics(
        liveRegion: true,
        child: Transform.rotate(
          angle: reducedMotion ? 0 : -0.06,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: 1.5,
                foreground:
                    Paint()
                      ..shader = LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors:
                            correct
                                ? [
                                  [
                                    const Color(0xFFEDFFF4),
                                    const Color(0xFF38DE9A),
                                  ],
                                  [
                                    const Color(0xFFE9FBFF),
                                    const Color(0xFF48BFFF),
                                  ],
                                  [
                                    const Color(0xFFFFF6B4),
                                    const Color(0xFFFFAA3C),
                                  ],
                                  [
                                    const Color(0xFFFFE5FF),
                                    const Color(0xFFDB75FF),
                                  ],
                                  [
                                    Colors.white,
                                    const Color(0xFFFFD34C),
                                    const Color(0xFFFF8A32),
                                  ],
                                ][streak.clamp(1, 5) - 1]
                                : [const Color(0xFFFFD9DE), color],
                      ).createShader(const Rect.fromLTWH(0, 0, 320, 72)),
                shadows: const [
                  Shadow(color: Color(0xFF101C2B), offset: Offset(-2, -2)),
                  Shadow(color: Color(0xFF101C2B), offset: Offset(2, -2)),
                  Shadow(color: Color(0xFF101C2B), offset: Offset(-2, 2)),
                  Shadow(color: Color(0xFF101C2B), offset: Offset(2, 2)),
                  Shadow(color: Color(0xFF101C2B), offset: Offset(-3, 0)),
                  Shadow(color: Color(0xFF101C2B), offset: Offset(3, 0)),
                  Shadow(color: Color(0xFF101C2B), offset: Offset(0, -3)),
                  Shadow(color: Color(0xFF101C2B), offset: Offset(0, 3)),
                  Shadow(
                    color: Color(0xCC000000),
                    offset: Offset(5, 7),
                    blurRadius: 4,
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

String correctAnswerSpeech(String answer, int streak) {
  final encouragement =
      [
        'よく知ってるね！',
        '2問連続正解！いい調子だね！',
        '3問連続正解！すごい、物知りだね！',
        '4問連続正解！その調子、あと少しだよ！',
        '5問連続正解！全問クリア、お見事だよ！',
      ][streak.clamp(1, 5) - 1];
  return '正解！答えは「$answer」だよ。$encouragement';
}

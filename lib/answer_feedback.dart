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
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                correct ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: color,
                size: 72,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';

const answerFeedbackDuration = Duration(milliseconds: 850);

/// Shared answer feedback for practice and conquest, with bounded motion.
class AnswerFeedback extends StatelessWidget {
  const AnswerFeedback({
    super.key,
    required this.correct,
    required this.answer,
    this.autoDismiss = false,
  });

  final bool correct, autoDismiss;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final color = correct ? const Color(0xFF7AE1BB) : const Color(0xFFFF8080);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: answerFeedbackDuration,
      onEnd: autoDismiss ? () => Navigator.of(context).pop() : null,
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
                correct ? '正解！' : '不正解',
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('正解は「$answer」', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
